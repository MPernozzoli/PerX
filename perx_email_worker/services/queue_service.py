"""
Persistent Email Queue Service
Coda persistente SQLite per processamento email asincrono.
"""
import sqlite3
import json
import logging
import os
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional
from enum import Enum
from threading import Lock

logger = logging.getLogger(__name__)


class QueueStatus(str, Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    RETRY = "retry"


class EmailQueueService:
    """
    Coda persistente per email.
    
    Funzionalità:
    - Persistenza SQLite
    - Deduplicazione per Message-ID
    - Gestione multi-utente (email condivise)
    - Retry con backoff esponenziale
    - Pulizia automatica elementi completati
    """
    
    def __init__(self, db_path: str = "data/email_queue.db"):
        self.db_path = db_path
        self._lock = Lock()
        self._init_db()
    
    def _init_db(self):
        """Inizializza database SQLite"""
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        
        with self._get_connection() as conn:
            conn.executescript("""
                -- Coda email principale
                CREATE TABLE IF NOT EXISTS email_queue (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    message_id TEXT UNIQUE NOT NULL,
                    account_id TEXT NOT NULL,
                    status TEXT DEFAULT 'pending',
                    priority INTEGER DEFAULT 0,
                    retry_count INTEGER DEFAULT 0,
                    max_retries INTEGER DEFAULT 3,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    scheduled_at TIMESTAMP,
                    started_at TIMESTAMP,
                    completed_at TIMESTAMP,
                    last_error TEXT,
                    email_data TEXT NOT NULL,
                    result_data TEXT
                );
                
                -- Indici per performance
                CREATE INDEX IF NOT EXISTS idx_queue_status ON email_queue(status);
                CREATE INDEX IF NOT EXISTS idx_queue_priority ON email_queue(priority DESC, created_at ASC);
                CREATE INDEX IF NOT EXISTS idx_queue_message_id ON email_queue(message_id);
                
                -- Mapping email -> utenti (per email condivise)
                CREATE TABLE IF NOT EXISTS email_recipients (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    message_id TEXT NOT NULL,
                    user_id TEXT NOT NULL,
                    is_primary BOOLEAN DEFAULT 0,
                    is_read BOOLEAN DEFAULT 0,
                    read_at TIMESTAMP,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE(message_id, user_id)
                );
                
                CREATE INDEX IF NOT EXISTS idx_recipients_message ON email_recipients(message_id);
                CREATE INDEX IF NOT EXISTS idx_recipients_user ON email_recipients(user_id);
                
                -- Message-ID già processati (per deduplicazione persistente)
                CREATE TABLE IF NOT EXISTS processed_messages (
                    message_id TEXT PRIMARY KEY,
                    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    result TEXT
                );
                
                -- Pulizia vecchi record dopo 30 giorni
                CREATE INDEX IF NOT EXISTS idx_processed_date ON processed_messages(processed_at);
            """)
            conn.commit()
            logger.info(f"Email queue database initialized: {self.db_path}")
    
    def _get_connection(self) -> sqlite3.Connection:
        """Ottiene connessione thread-safe"""
        conn = sqlite3.connect(self.db_path, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        return conn
    
    # ========== Deduplicazione ==========
    
    def is_already_processed(self, message_id: str) -> bool:
        """Verifica se un message_id è già stato processato"""
        with self._lock:
            with self._get_connection() as conn:
                cursor = conn.execute(
                    "SELECT 1 FROM processed_messages WHERE message_id = ?",
                    (message_id,)
                )
                return cursor.fetchone() is not None
    
    def is_in_queue(self, message_id: str) -> bool:
        """Verifica se un message_id è già in coda"""
        with self._lock:
            with self._get_connection() as conn:
                cursor = conn.execute(
                    "SELECT 1 FROM email_queue WHERE message_id = ? AND status NOT IN ('completed', 'failed')",
                    (message_id,)
                )
                return cursor.fetchone() is not None
    
    def mark_as_processed(self, message_id: str, result: Optional[str] = None):
        """Marca un message_id come processato"""
        with self._lock:
            with self._get_connection() as conn:
                conn.execute(
                    "INSERT OR REPLACE INTO processed_messages (message_id, result) VALUES (?, ?)",
                    (message_id, result)
                )
                conn.commit()
    
    # ========== Gestione Multi-Utente ==========
    
    def add_email_recipients(self, message_id: str, user_ids: List[str], primary_user_id: str):
        """
        Registra i destinatari di una email.
        Una email può essere mostrata a più utenti.
        """
        with self._lock:
            with self._get_connection() as conn:
                for user_id in user_ids:
                    conn.execute("""
                        INSERT OR IGNORE INTO email_recipients 
                        (message_id, user_id, is_primary) 
                        VALUES (?, ?, ?)
                    """, (message_id, user_id, user_id == primary_user_id))
                conn.commit()
    
    def get_email_recipients(self, message_id: str) -> List[Dict]:
        """Ottiene tutti i destinatari di una email"""
        with self._get_connection() as conn:
            cursor = conn.execute(
                "SELECT user_id, is_primary, is_read, read_at FROM email_recipients WHERE message_id = ?",
                (message_id,)
            )
            return [dict(row) for row in cursor.fetchall()]
    
    def mark_email_read_for_user(self, message_id: str, user_id: str):
        """Marca email come letta per un utente specifico"""
        with self._lock:
            with self._get_connection() as conn:
                conn.execute("""
                    UPDATE email_recipients 
                    SET is_read = 1, read_at = CURRENT_TIMESTAMP 
                    WHERE message_id = ? AND user_id = ?
                """, (message_id, user_id))
                conn.commit()
    
    def get_unread_for_user(self, user_id: str, limit: int = 100) -> List[str]:
        """Ottiene message_id non letti per un utente"""
        with self._get_connection() as conn:
            cursor = conn.execute("""
                SELECT message_id FROM email_recipients 
                WHERE user_id = ? AND is_read = 0 
                ORDER BY created_at DESC LIMIT ?
            """, (user_id, limit))
            return [row['message_id'] for row in cursor.fetchall()]
    
    # ========== Gestione Coda ==========
    
    def enqueue(self, email_data: Dict, priority: int = 0) -> bool:
        """
        Aggiunge email alla coda.
        
        Returns:
            True se aggiunta, False se già presente (deduplicated)
        """
        message_id = email_data.get('message_id', '')
        if not message_id:
            logger.warning("Email without message_id, generating hash")
            import hashlib
            content = f"{email_data.get('subject', '')}{email_data.get('date', '')}{email_data.get('from', {}).get('email', '')}"
            message_id = hashlib.sha256(content.encode()).hexdigest()[:40]
            email_data['message_id'] = message_id
        
        # Check deduplication
        if self.is_already_processed(message_id):
            logger.debug(f"Message already processed: {message_id}")
            return False
        
        if self.is_in_queue(message_id):
            logger.debug(f"Message already in queue: {message_id}")
            return False
        
        # Determina utenti destinatari
        account_id = email_data.get('account_id', '')
        to_addresses = email_data.get('to', [])
        cc_addresses = email_data.get('cc', [])
        
        # Inserisci in coda
        with self._lock:
            with self._get_connection() as conn:
                try:
                    conn.execute("""
                        INSERT INTO email_queue 
                        (message_id, account_id, priority, email_data, status)
                        VALUES (?, ?, ?, ?, 'pending')
                    """, (message_id, account_id, priority, json.dumps(email_data)))
                    conn.commit()
                    logger.info(f"Email enqueued: {message_id[:20]}...")
                    return True
                except sqlite3.IntegrityError:
                    # Già presente
                    return False
    
    def dequeue(self, batch_size: int = 5) -> List[Dict]:
        """
        Preleva batch di email dalla coda per il processing.
        Marca come 'processing' atomicamente.
        """
        with self._lock:
            with self._get_connection() as conn:
                # Seleziona pending ordinati per priorità e data
                cursor = conn.execute("""
                    SELECT id, message_id, email_data FROM email_queue
                    WHERE status = 'pending'
                    ORDER BY priority DESC, created_at ASC
                    LIMIT ?
                """, (batch_size,))
                
                rows = cursor.fetchall()
                if not rows:
                    return []
                
                # Marca come processing
                ids = [row['id'] for row in rows]
                placeholders = ','.join('?' * len(ids))
                conn.execute(f"""
                    UPDATE email_queue 
                    SET status = 'processing', started_at = CURRENT_TIMESTAMP
                    WHERE id IN ({placeholders})
                """, ids)
                conn.commit()
                
                return [{
                    'queue_id': row['id'],
                    'message_id': row['message_id'],
                    'email_data': json.loads(row['email_data'])
                } for row in rows]
    
    def complete(self, queue_id: int, result_data: Optional[Dict] = None):
        """Marca un item come completato"""
        with self._lock:
            with self._get_connection() as conn:
                # Ottieni message_id prima
                cursor = conn.execute(
                    "SELECT message_id FROM email_queue WHERE id = ?", 
                    (queue_id,)
                )
                row = cursor.fetchone()
                if row:
                    message_id = row['message_id']
                    # Marca come processato per deduplicazione futura
                    self.mark_as_processed(message_id, json.dumps(result_data) if result_data else None)
                
                conn.execute("""
                    UPDATE email_queue 
                    SET status = 'completed', completed_at = CURRENT_TIMESTAMP,
                        result_data = ?
                    WHERE id = ?
                """, (json.dumps(result_data) if result_data else None, queue_id))
                conn.commit()
    
    def fail(self, queue_id: int, error: str):
        """Marca un item come fallito (con possibile retry)"""
        with self._lock:
            with self._get_connection() as conn:
                cursor = conn.execute(
                    "SELECT retry_count, max_retries FROM email_queue WHERE id = ?",
                    (queue_id,)
                )
                row = cursor.fetchone()
                if not row:
                    return
                
                retry_count = row['retry_count'] + 1
                max_retries = row['max_retries']
                
                if retry_count < max_retries:
                    # Schedula retry con backoff esponenziale
                    backoff_seconds = 60 * (2 ** retry_count)  # 2min, 4min, 8min...
                    scheduled_at = datetime.now() + timedelta(seconds=backoff_seconds)
                    
                    conn.execute("""
                        UPDATE email_queue 
                        SET status = 'retry', retry_count = ?, last_error = ?,
                            scheduled_at = ?
                        WHERE id = ?
                    """, (retry_count, error, scheduled_at.isoformat(), queue_id))
                else:
                    # Max retry raggiunto
                    conn.execute("""
                        UPDATE email_queue 
                        SET status = 'failed', retry_count = ?, last_error = ?,
                            completed_at = CURRENT_TIMESTAMP
                        WHERE id = ?
                    """, (retry_count, error, queue_id))
                
                conn.commit()
    
    def requeue_retries(self) -> int:
        """Rimette in coda i retry scaduti"""
        with self._lock:
            with self._get_connection() as conn:
                now = datetime.now().isoformat()
                cursor = conn.execute("""
                    UPDATE email_queue 
                    SET status = 'pending', started_at = NULL
                    WHERE status = 'retry' AND scheduled_at <= ?
                """, (now,))
                conn.commit()
                return cursor.rowcount
    
    def get_stats(self) -> Dict:
        """Statistiche della coda"""
        with self._get_connection() as conn:
            stats = {}
            for status in QueueStatus:
                cursor = conn.execute(
                    "SELECT COUNT(*) as count FROM email_queue WHERE status = ?",
                    (status.value,)
                )
                stats[status.value] = cursor.fetchone()['count']
            
            cursor = conn.execute("SELECT COUNT(*) as count FROM processed_messages")
            stats['total_processed'] = cursor.fetchone()['count']
            
            return stats
    
    def cleanup_old(self, days: int = 7):
        """Pulisce record vecchi completati/falliti"""
        with self._lock:
            with self._get_connection() as conn:
                cutoff = (datetime.now() - timedelta(days=days)).isoformat()
                
                # Pulisci coda
                cursor = conn.execute("""
                    DELETE FROM email_queue 
                    WHERE status IN ('completed', 'failed') AND completed_at < ?
                """, (cutoff,))
                queue_deleted = cursor.rowcount
                
                # Pulisci processed (30 giorni)
                cutoff_processed = (datetime.now() - timedelta(days=30)).isoformat()
                cursor = conn.execute(
                    "DELETE FROM processed_messages WHERE processed_at < ?",
                    (cutoff_processed,)
                )
                processed_deleted = cursor.rowcount
                
                conn.commit()
                logger.info(f"Cleanup: {queue_deleted} queue items, {processed_deleted} processed records")
