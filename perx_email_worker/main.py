#!/usr/bin/env python3
"""
PerX Email Worker
Worker Python per gestione email IMAP/SMTP con:
- Coda persistente (SQLite)
- Deduplicazione per Message-ID
- Gestione multi-utente (email condivise)
- Fetch: ultimi 7 giorni + tutte le non lette

Comunica con l'Hub Swift via HTTP.
"""
import os
import sys
import time
import json
import asyncio
import logging
import requests
import uvicorn
from datetime import datetime
from threading import Thread, Event
from typing import List, Dict, Any, Set, Optional
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from config import (
    HUB_URL, IMAP_POLL_INTERVAL, SCHEDULED_CHECK_INTERVAL,
    LOG_LEVEL, LOG_FILE, load_accounts, FETCH_DAYS
)
from services.imap_service import IMAPService
from services.smtp_service import SMTPService
from services.queue_service import EmailQueueService, QueueStatus
from services.token_service import get_token_service, TokenService

__version__ = "2.1.0"  # Auto-reconnect, keep-alive, improved error handling
START_TIME = datetime.now()

# Logging setup
os.makedirs('logs', exist_ok=True)
os.makedirs('data', exist_ok=True)

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('email_worker')


class EmailWorker:
    """
    Worker principale per email.
    
    Funzionalità:
    1. Poll IMAP per nuove email (ultimi 7 giorni + non lette)
    2. Coda persistente SQLite
    3. Deduplicazione per Message-ID (anche multi-account)
    4. Gestione email condivise (stesso messaggio a più utenti)
    5. Invio email all'Hub per processing
    6. Check email programmate e invio
    7. Marca email come lette su tutti gli account
    """
    
    def __init__(self, hub_url: str):
        self.hub_url = hub_url.rstrip('/')
        self.imap_service = IMAPService(hub_url, fetch_days=FETCH_DAYS)
        self.smtp_service = SMTPService(hub_url)
        self.queue_service = EmailQueueService()
        self.stop_event = Event()
        self.accounts: List[Dict] = []
        self._session_seen_ids: Set[str] = set()  # Message-ID visti in questa sessione
        
    def start(self):
        """Avvia il worker"""
        logger.info(f"Starting Email Worker v{__version__} - Hub: {self.hub_url}")
        
        # Load accounts from config
        self._load_accounts()
        
        # Start threads
        imap_thread = Thread(target=self._imap_loop, daemon=True, name="IMAP-Poller")
        processor_thread = Thread(target=self._processor_loop, daemon=True, name="Queue-Processor")
        scheduled_thread = Thread(target=self._scheduled_loop, daemon=True, name="Scheduled-Sender")
        cleanup_thread = Thread(target=self._cleanup_loop, daemon=True, name="Cleanup")
        keepalive_thread = Thread(target=self._keepalive_loop, daemon=True, name="KeepAlive")
        account_refresh_thread = Thread(target=self._account_refresh_loop, daemon=True, name="AccountRefresh")
        
        imap_thread.start()
        processor_thread.start()
        scheduled_thread.start()
        cleanup_thread.start()
        keepalive_thread.start()
        account_refresh_thread.start()
        
        logger.info("All worker threads started")
        
        try:
            while not self.stop_event.is_set():
                time.sleep(1)
        except KeyboardInterrupt:
            logger.info("Shutdown requested...")
            self.stop()
    
    def stop(self):
        """Ferma il worker"""
        self.stop_event.set()
        self.imap_service.disconnect_all()
        logger.info("Email Worker stopped")
    
    def _load_accounts(self):
        """
        Carica account email.
        
        Prima prova dal TokenService (token registrati dall'Hub),
        poi fallback su accounts.json per compatibilità.
        """
        try:
            # Prima: carica da TokenService (preferito)
            token_service = get_token_service()
            token_users = token_service.list_users()
            
            if token_users:
                self.accounts = []
                for user in token_users:
                    user_id = user.get('user_id')
                    email_addr = user.get('email')
                    
                    # Ottieni access_token per questo utente
                    access_token = token_service.get_access_token(user_id)
                    
                    if access_token:
                        self.accounts.append({
                            'user_id': user_id,
                            'email': email_addr,
                            'oauth_token': access_token
                        })
                        self.imap_service.register_account(user_id, email_addr)
                
                if self.accounts:
                    user_ids = [a.get('user_id') for a in self.accounts]
                    logger.info(f"Loaded {len(self.accounts)} accounts from TokenService: {', '.join(user_ids)}")
                    return
            
            # Fallback: carica da accounts.json
            self.accounts = load_accounts()
            if self.accounts:
                for acc in self.accounts:
                    user_id = acc.get('user_id', acc.get('id', 'unknown'))
                    email_addr = acc.get('email', '')
                    self.imap_service.register_account(user_id, email_addr)
                
                user_ids = [a.get('user_id', a.get('id', 'unknown')) for a in self.accounts]
                logger.info(f"Loaded {len(self.accounts)} email accounts from config: {', '.join(user_ids)}")
            else:
                logger.warning("No email accounts configured. Waiting for token registration from Hub.")
        except Exception as e:
            logger.error(f"Failed to load accounts: {e}")
            self.accounts = []
    
    def _reload_accounts_from_tokens(self):
        """Ricarica gli account dopo registrazione nuovo token"""
        logger.info("Reloading accounts after token registration...")
        self._load_accounts()
    
    # ========== IMAP Polling ==========
    
    def _imap_loop(self):
        """Loop di polling IMAP con gestione robusta degli errori"""
        # Prima fetch: carica i message_id già processati
        self._load_processed_ids()
        
        consecutive_errors = 0
        max_consecutive_errors = 5
        
        while not self.stop_event.is_set():
            try:
                self._check_all_accounts()
                consecutive_errors = 0  # Reset su successo
            except Exception as e:
                consecutive_errors += 1
                logger.error(f"Error in IMAP loop ({consecutive_errors}/{max_consecutive_errors}): {e}", exc_info=True)
                
                # Se troppi errori consecutivi, forza riconnessione di tutti gli account
                if consecutive_errors >= max_consecutive_errors:
                    logger.warning("Too many consecutive errors, forcing reconnection of all accounts")
                    self.imap_service.disconnect_all()
                    consecutive_errors = 0
                    # Aspetta un po' prima di riprovare
                    time.sleep(30)
            
            # Wait for next poll
            for _ in range(IMAP_POLL_INTERVAL):
                if self.stop_event.is_set():
                    return
                time.sleep(1)
    
    def _load_processed_ids(self):
        """Carica message_id già processati per deduplicazione"""
        # I message_id processati sono persistiti in SQLite
        # Li carichiamo all'avvio per evitare riprocessamento
        pass  # La deduplicazione avviene in queue_service.enqueue()
    
    def _check_all_accounts(self):
        """Controlla nuove email su tutti gli account"""
        all_seen_this_round: Set[str] = set()
        
        for account in self.accounts:
            try:
                emails, seen = self._check_account(account, all_seen_this_round)
                all_seen_this_round.update(seen)
                
                # Enqueue emails
                for email_data in emails:
                    # Priorità: non lette hanno priorità più alta
                    priority = 10 if not email_data.get('is_read', True) else 0
                    
                    if self.queue_service.enqueue(email_data, priority=priority):
                        # Registra destinatari per email condivise
                        message_id = email_data.get('message_id', '')
                        recipient_users = email_data.get('recipient_users', [])
                        primary_user = email_data.get('account_id', '')
                        
                        if recipient_users and message_id:
                            self.queue_service.add_email_recipients(
                                message_id, recipient_users, primary_user
                            )
                        
            except Exception as e:
                logger.error(f"Error checking account {account.get('user_id')}: {e}")
    
    def _check_account(self, account: Dict, already_seen: Set[str]) -> tuple:
        """Controlla nuove email per un account"""
        account_id = account.get('user_id', account.get('id'))
        email_addr = account.get('email')
        
        # Ottieni sempre un token fresco dal TokenService
        token_service = get_token_service()
        oauth_token = token_service.get_access_token(account_id)
        
        if not oauth_token:
            # Fallback al token salvato nell'account
            oauth_token = account.get('oauth_token')
        
        if not oauth_token:
            logger.warning(f"No OAuth token for account {account_id}")
            return [], set()
        
        # Aggiorna il token nel servizio IMAP (per riconnessioni future)
        self.imap_service.update_token(account_id, oauth_token)
        
        # Connect if needed (ensure_connection viene chiamato dentro fetch_emails)
        if account_id not in self.imap_service._connections:
            if not self.imap_service.connect(account_id, email_addr, oauth_token):
                return [], set()
        
        # Combina seen_ids: sessione corrente + già visti in questo round
        combined_seen = self._session_seen_ids | already_seen
        
        # Fetch emails
        emails, session_seen = self.imap_service.fetch_emails(
            account_id, 
            seen_message_ids=combined_seen
        )
        
        # Update session seen
        self._session_seen_ids.update(session_seen)
        
        if emails:
            logger.info(f"Fetched {len(emails)} emails from {account_id}")
        
        return emails, session_seen
    
    # ========== Queue Processing ==========
    
    def _processor_loop(self):
        """Loop di processamento coda"""
        while not self.stop_event.is_set():
            try:
                # Requeue retry scaduti
                requeued = self.queue_service.requeue_retries()
                if requeued:
                    logger.info(f"Requeued {requeued} retries")
                
                # Process batch
                batch = self.queue_service.dequeue(batch_size=5)
                
                for item in batch:
                    self._process_queue_item(item)
                
                if not batch:
                    # Nessun item, aspetta un po'
                    time.sleep(2)
                    
            except Exception as e:
                logger.error(f"Error in processor loop: {e}", exc_info=True)
                time.sleep(5)
    
    def _process_queue_item(self, item: Dict):
        """Processa un item dalla coda"""
        queue_id = item['queue_id']
        message_id = item['message_id']
        email_data = item['email_data']
        
        try:
            # Invia all'Hub
            result = self._send_to_hub(email_data)
            
            if result.get('success'):
                self.queue_service.complete(queue_id, result)
                logger.debug(f"Processed: {message_id[:30]}...")
                
                # Se l'Hub richiede di marcare come letta
                if result.get('mark_as_read'):
                    self._mark_read_on_all_accounts(message_id)
            else:
                error = result.get('error', 'Unknown error')
                self.queue_service.fail(queue_id, error)
                logger.warning(f"Hub rejected: {message_id[:30]}... - {error}")
                
        except Exception as e:
            self.queue_service.fail(queue_id, str(e))
            logger.error(f"Processing failed: {message_id[:30]}... - {e}")
    
    def _send_to_hub(self, email_data: Dict) -> Dict:
        """Invia email all'Hub per processing"""
        try:
            url = f"{self.hub_url}/internal/email/received"
            response = requests.post(url, json=email_data, timeout=30)
            
            if response.status_code == 200:
                return response.json()
            else:
                return {
                    'success': False, 
                    'error': f"HTTP {response.status_code}: {response.text[:200]}"
                }
                
        except requests.Timeout:
            return {'success': False, 'error': 'Hub timeout'}
        except Exception as e:
            return {'success': False, 'error': str(e)}
    
    def _mark_read_on_all_accounts(self, message_id: str):
        """Marca email come letta su tutti gli account Gmail"""
        marked = self.imap_service.mark_as_read_all_accounts(message_id)
        if marked:
            logger.debug(f"Marked as read on {marked} accounts: {message_id[:30]}...")
    
    # ========== Scheduled Emails ==========
    
    def _scheduled_loop(self):
        """Loop per invio email programmate"""
        while not self.stop_event.is_set():
            try:
                self._check_scheduled_emails()
            except Exception as e:
                logger.error(f"Error in scheduled loop: {e}")
            
            # Wait for next check
            for _ in range(SCHEDULED_CHECK_INTERVAL):
                if self.stop_event.is_set():
                    return
                time.sleep(1)
    
    def _check_scheduled_emails(self):
        """Controlla e invia email programmate.
        L'Hub restituisce solo email con scheduledAt <= now, quindi inviamo direttamente.
        """
        try:
            url = f"{self.hub_url}/internal/email/scheduled/pending"
            response = requests.get(url, timeout=10)
            
            if response.status_code != 200:
                return
            
            scheduled = response.json()
            
            if scheduled:
                logger.info(f"Found {len(scheduled)} scheduled emails ready to send")
            
            for email in scheduled:
                self._send_scheduled_email(email)
                    
        except Exception as e:
            logger.error(f"Error checking scheduled emails: {e}")
    
    def _send_scheduled_email(self, scheduled_email: Dict):
        """Invia email programmata.
        Formato atteso da Hub:
        - id: string
        - accountId: string
        - to: [string] - lista destinatari
        - cc: [string] opzionale
        - subject: string
        - body: string (HTML)
        - scheduledAt: ISO date
        - status: string
        - sinistroRef: string opzionale
        """
        email_id = scheduled_email.get('id')
        account_id = scheduled_email.get('accountId')
        
        logger.info(f"Sending scheduled email {email_id} for account {account_id}")
        
        # Get account token (cerca per user_id che corrisponde a accountId)
        account = next((a for a in self.accounts 
                       if a.get('user_id') == account_id or a.get('id') == account_id), None)
        
        # Se non trovato, prova a cercare per email
        if not account:
            account = next((a for a in self.accounts 
                           if a.get('email', '').lower() == account_id.lower()), None)
        
        if not account:
            logger.error(f"Account not found for scheduled email: {account_id}")
            self._mark_scheduled_failed(email_id, f"Account not found: {account_id}")
            return
        
        # Ottieni token fresco
        token_service = get_token_service()
        user_id = account.get('user_id')
        oauth_token = token_service.get_access_token(user_id) if user_id else account.get('oauth_token')
        
        if not oauth_token:
            logger.error(f"No OAuth token for scheduled email account: {account_id}")
            self._mark_scheduled_failed(email_id, "No valid OAuth token")
            return
        
        # Prepara dati per SMTP service
        send_data = {
            'accountId': account_id,
            'accountEmail': account.get('email'),
            'to': scheduled_email.get('to', []),
            'cc': scheduled_email.get('cc'),
            'subject': scheduled_email.get('subject', ''),
            'body': scheduled_email.get('body', ''),
            'attachments': None  # TODO: supporto allegati scheduled
        }
        
        # Send via SMTP
        result = self.smtp_service.send_scheduled(send_data, oauth_token)
        
        if result['success']:
            logger.info(f"✅ Scheduled email {email_id} sent successfully: {result['message_id']}")
            self._mark_scheduled_sent(email_id, result['message_id'])
        else:
            logger.error(f"❌ Scheduled email {email_id} failed: {result['error']}")
            self._mark_scheduled_failed(email_id, result['error'])
    
    def _mark_scheduled_sent(self, email_id: str, message_id: str):
        """Marca email programmata come inviata"""
        try:
            url = f"{self.hub_url}/internal/email/scheduled/{email_id}/sent"
            requests.post(url, json={'messageId': message_id}, timeout=10)
        except Exception as e:
            logger.error(f"Failed to mark scheduled as sent: {e}")
    
    def _mark_scheduled_failed(self, email_id: str, error: str):
        """Marca email programmata come fallita"""
        try:
            url = f"{self.hub_url}/internal/email/scheduled/{email_id}/failed"
            requests.post(url, json={'error': error}, timeout=10)
        except Exception as e:
            logger.error(f"Failed to mark scheduled as failed: {e}")
    
    # ========== Keep-Alive ==========
    
    def _keepalive_loop(self):
        """
        Loop per mantenere le connessioni IMAP attive.
        Gmail disconnette le connessioni inattive dopo ~30 minuti.
        Inviamo NOOP ogni 5 minuti per mantenerle attive.
        """
        KEEPALIVE_INTERVAL = 300  # 5 minuti
        
        while not self.stop_event.is_set():
            try:
                # Aspetta l'intervallo
                for _ in range(KEEPALIVE_INTERVAL):
                    if self.stop_event.is_set():
                        return
                    time.sleep(1)
                
                # Invia NOOP a tutte le connessioni attive
                active_accounts = list(self.imap_service._connections.keys())
                for account_id in active_accounts:
                    try:
                        if self.imap_service._is_connection_alive(account_id):
                            logger.debug(f"Keep-alive OK for {account_id}")
                        else:
                            logger.warning(f"Keep-alive failed for {account_id}, will reconnect on next fetch")
                    except Exception as e:
                        logger.warning(f"Keep-alive error for {account_id}: {e}")
                
            except Exception as e:
                logger.error(f"Error in keepalive loop: {e}")
    
    # ========== Account Refresh ==========
    
    def _account_refresh_loop(self):
        """
        Loop per ricaricare periodicamente gli account dal TokenService.
        Permette di rilevare nuovi account registrati o token aggiornati.
        """
        REFRESH_INTERVAL = 300  # 5 minuti
        
        while not self.stop_event.is_set():
            try:
                # Aspetta l'intervallo
                for _ in range(REFRESH_INTERVAL):
                    if self.stop_event.is_set():
                        return
                    time.sleep(1)
                
                # Ricarica gli account
                old_count = len(self.accounts)
                self._load_accounts()
                new_count = len(self.accounts)
                
                if new_count != old_count:
                    logger.info(f"Account count changed: {old_count} -> {new_count}")
                
            except Exception as e:
                logger.error(f"Error in account refresh loop: {e}")
    
    # ========== Cleanup ==========
    
    def _cleanup_loop(self):
        """Loop pulizia periodica"""
        while not self.stop_event.is_set():
            try:
                # Cleanup ogni ora
                for _ in range(3600):
                    if self.stop_event.is_set():
                        return
                    time.sleep(1)
                
                self.queue_service.cleanup_old(days=7)
                
            except Exception as e:
                logger.error(f"Error in cleanup loop: {e}")


# Global worker instance
worker: Optional[EmailWorker] = None


# FastAPI app with lifespan
@asynccontextmanager
async def lifespan(app: FastAPI):
    global worker
    hub_url = os.environ.get('HUB_URL', HUB_URL)
    worker = EmailWorker(hub_url)
    
    # Start worker in background thread
    worker_thread = Thread(target=worker.start, daemon=True, name="EmailWorker-Main")
    worker_thread.start()
    
    yield
    
    # Shutdown
    if worker:
        worker.stop()


app = FastAPI(
    title="PerX Email Worker",
    version=__version__,
    lifespan=lifespan
)


# ========== API Models ==========

class HealthResponse(BaseModel):
    status: str
    version: str
    uptime: float
    accounts_count: int
    hub_url: str
    queue_stats: Dict[str, int]
    connections: Dict[str, bool] = {}  # account_id -> is_connected


class MarkReadRequest(BaseModel):
    message_id: str
    user_id: Optional[str] = None


class QueueStatsResponse(BaseModel):
    pending: int
    processing: int
    completed: int
    failed: int
    retry: int
    total_processed: int


class RegisterTokenRequest(BaseModel):
    user_id: str
    email: str
    refresh_token: str


class TokenStatusResponse(BaseModel):
    user_id: str
    email: Optional[str]
    is_valid: bool
    has_token: bool


class UserTokenInfo(BaseModel):
    user_id: str
    email: str
    stored_at: str


# ========== API Endpoints ==========

@app.get("/health", response_model=HealthResponse)
async def health():
    """Health check endpoint"""
    uptime = (datetime.now() - START_TIME).total_seconds()
    accounts_count = len(worker.accounts) if worker else 0
    hub_url = worker.hub_url if worker else HUB_URL
    queue_stats = worker.queue_service.get_stats() if worker else {}
    
    # Stato connessioni IMAP
    connections = {}
    if worker:
        for acc in worker.accounts:
            acc_id = acc.get('user_id', acc.get('id', 'unknown'))
            connections[acc_id] = acc_id in worker.imap_service._connections
    
    return HealthResponse(
        status="ok",
        version=__version__,
        uptime=uptime,
        accounts_count=accounts_count,
        hub_url=hub_url,
        queue_stats=queue_stats,
        connections=connections
    )


@app.get("/queue/stats", response_model=QueueStatsResponse)
async def queue_stats():
    """Statistiche della coda"""
    if not worker:
        raise HTTPException(status_code=503, detail="Worker not ready")
    
    stats = worker.queue_service.get_stats()
    return QueueStatsResponse(**stats)


@app.post("/email/mark-read")
async def mark_email_read(request: MarkReadRequest):
    """Marca email come letta"""
    if not worker:
        raise HTTPException(status_code=503, detail="Worker not ready")
    
    message_id = request.message_id
    user_id = request.user_id
    
    # Marca in coda locale
    if user_id:
        worker.queue_service.mark_email_read_for_user(message_id, user_id)
    
    # Marca su IMAP
    marked = worker.imap_service.mark_as_read_all_accounts(message_id)
    
    return {"success": True, "marked_accounts": marked}


class SendEmailRequest(BaseModel):
    """Richiesta per invio email immediato"""
    account_id: str
    to: List[str]
    cc: Optional[List[str]] = None
    bcc: Optional[List[str]] = None
    subject: str
    body: str
    is_html: bool = True
    reply_to_thread_id: Optional[str] = None
    in_reply_to: Optional[str] = None
    references: Optional[str] = None
    attachments: Optional[List[Dict[str, Any]]] = None


class SendEmailResponse(BaseModel):
    """Risposta invio email"""
    success: bool
    message_id: Optional[str] = None
    error: Optional[str] = None


@app.post("/email/send", response_model=SendEmailResponse)
async def send_email(request: SendEmailRequest):
    """
    Invia email immediatamente via Gmail SMTP.
    Chiamato dall'Hub per invio diretto.
    """
    if not worker:
        raise HTTPException(status_code=503, detail="Worker not ready")
    
    account_id = request.account_id
    
    # Trova account
    account = next((a for a in worker.accounts 
                   if a.get('user_id') == account_id or a.get('id') == account_id), None)
    
    # Se non trovato, prova per email
    if not account:
        account = next((a for a in worker.accounts 
                       if a.get('email', '').lower() == account_id.lower()), None)
    
    if not account:
        return SendEmailResponse(success=False, error=f"Account not found: {account_id}")
    
    # Ottieni token fresco
    token_service = get_token_service()
    user_id = account.get('user_id')
    oauth_token = token_service.get_access_token(user_id) if user_id else account.get('oauth_token')
    
    if not oauth_token:
        return SendEmailResponse(success=False, error="No valid OAuth token")
    
    # Prepara email
    email_address = account.get('email')
    
    # Invia via SMTP
    result = worker.smtp_service.send_email(
        account_id=account_id,
        email_address=email_address,
        oauth_token=oauth_token,
        to=request.to,
        subject=request.subject,
        body_html=request.body if request.is_html else None,
        body_text=request.body if not request.is_html else None,
        cc=request.cc,
        attachments=request.attachments
    )
    
    if result['success']:
        logger.info(f"✅ Email sent: {request.subject} -> {request.to}")
        return SendEmailResponse(success=True, message_id=result['message_id'])
    else:
        logger.error(f"❌ Email send failed: {result['error']}")
        return SendEmailResponse(success=False, error=result['error'])


@app.post("/restart")
async def restart():
    """Restart the worker"""
    asyncio.create_task(delayed_shutdown())
    return {"status": "restarting"}


# ========== Token Management Endpoints ==========

@app.post("/auth/register-token")
async def register_token(request: RegisterTokenRequest):
    """
    Registra un refresh_token per un utente.
    Chiamato dall'Hub quando il client si autentica.
    """
    token_service = get_token_service()
    
    success = token_service.store_refresh_token(
        user_id=request.user_id,
        email=request.email,
        refresh_token=request.refresh_token
    )
    
    if success:
        # Trigger reload degli account nel worker
        if worker:
            worker._reload_accounts_from_tokens()
        
        return {"success": True, "message": f"Token registered for {request.user_id}"}
    else:
        raise HTTPException(status_code=500, detail="Failed to store token")


@app.get("/auth/status/{user_id}", response_model=TokenStatusResponse)
async def token_status(user_id: str):
    """Verifica lo stato del token per un utente"""
    token_service = get_token_service()
    
    has_token = token_service.has_valid_token(user_id)
    is_valid = False
    email = None
    
    if has_token:
        is_valid, email = token_service.validate_token(user_id)
    
    return TokenStatusResponse(
        user_id=user_id,
        email=email,
        is_valid=is_valid,
        has_token=has_token
    )


@app.delete("/auth/token/{user_id}")
async def delete_token(user_id: str):
    """Elimina il token per un utente (logout)"""
    token_service = get_token_service()
    
    success = token_service.delete_token(user_id)
    
    if success:
        return {"success": True, "message": f"Token deleted for {user_id}"}
    else:
        raise HTTPException(status_code=500, detail="Failed to delete token")


@app.get("/auth/users", response_model=List[UserTokenInfo])
async def list_users():
    """Lista tutti gli utenti con token registrati"""
    token_service = get_token_service()
    users = token_service.list_users()
    return [UserTokenInfo(**u) for u in users]


@app.post("/auth/refresh/{user_id}")
async def force_refresh_token(user_id: str):
    """Forza il refresh del token per un utente"""
    token_service = get_token_service()
    
    access_token = token_service.refresh_access_token(user_id)
    
    if access_token:
        return {"success": True, "message": "Token refreshed"}
    else:
        raise HTTPException(status_code=401, detail="Token refresh failed")


async def delayed_shutdown():
    await asyncio.sleep(1)
    os._exit(0)


def main():
    port = int(os.environ.get('PORT', 5001))
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")


if __name__ == '__main__':
    main()
