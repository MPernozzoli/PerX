"""
IMAP Service for fetching emails
Handles multi-account with deduplication.

Strategia di fetch:
1. Ultimi 7 giorni di email (lette e non lette)
2. Tutte le email non lette (senza limite temporale)
3. Deduplicazione per Message-ID
"""
import imaplib
import email
import base64
import hashlib
import logging
import socket
import ssl
from email.header import decode_header
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional, Set, Tuple

logger = logging.getLogger(__name__)

# Configurazione
DEFAULT_FETCH_DAYS = 7
MAX_EMAILS_PER_FETCH = 200  # Limite per evitare sovraccarico
IMAP_TIMEOUT = 60  # Timeout connessione in secondi
MAX_RECONNECT_ATTEMPTS = 3  # Tentativi di riconnessione


class IMAPService:
    """
    Servizio IMAP per scaricamento email con deduplicazione multi-account.
    
    Funzionalità:
    - Gestione multipli account Gmail con OAuth2
    - Fetch: ultimi 7 giorni + tutte le non lette
    - Deduplicazione per Message-ID (email in CC)
    - Estrazione allegati
    - Gestione multi-utente (identifica tutti i destinatari)
    - Riconnessione automatica in caso di disconnessione
    """
    
    def __init__(self, hub_url: str, fetch_days: int = DEFAULT_FETCH_DAYS):
        self.hub_url = hub_url.rstrip('/')
        self.fetch_days = fetch_days
        self._connections: Dict[str, imaplib.IMAP4_SSL] = {}
        # Mapping email -> user_id per tutti gli account configurati
        self._email_to_user: Dict[str, str] = {}
        # Store credentials for reconnection
        self._credentials: Dict[str, Dict[str, str]] = {}  # account_id -> {email, token}
        # Track connection health
        self._last_successful_op: Dict[str, datetime] = {}
    
    def register_account(self, user_id: str, email_address: str):
        """Registra mapping email -> user_id per deduplicazione multi-utente"""
        self._email_to_user[email_address.lower()] = user_id
    
    def get_user_for_email(self, email_address: str) -> Optional[str]:
        """Trova user_id per un indirizzo email"""
        return self._email_to_user.get(email_address.lower())
    
    def connect(self, account_id: str, email_addr: str, oauth_token: str) -> bool:
        """Connette a un account Gmail con OAuth2"""
        # Store credentials for potential reconnection
        self._credentials[account_id] = {'email': email_addr, 'token': oauth_token}
        
        try:
            # Close existing connection if any
            self._close_connection(account_id)
            
            # Create SSL context
            context = ssl.create_default_context()
            
            # Connect with timeout
            imap = imaplib.IMAP4_SSL('imap.gmail.com', 993, ssl_context=context, timeout=IMAP_TIMEOUT)
            
            # OAuth2 authentication string
            auth_string = f'user={email_addr}\x01auth=Bearer {oauth_token}\x01\x01'
            imap.authenticate('XOAUTH2', lambda x: auth_string.encode())
            
            self._connections[account_id] = imap
            self._last_successful_op[account_id] = datetime.now()
            self.register_account(account_id, email_addr)
            logger.info(f"Connected to IMAP for account: {account_id}")
            return True
            
        except imaplib.IMAP4.error as e:
            error_msg = str(e)
            if 'AUTHENTICATIONFAILED' in error_msg or 'Invalid credentials' in error_msg.lower():
                logger.error(f"OAuth token expired/invalid for {account_id}: {e}")
            else:
                logger.error(f"IMAP error for {account_id}: {e}")
            return False
        except (socket.timeout, socket.error) as e:
            logger.error(f"Network error connecting to IMAP for {account_id}: {e}")
            return False
        except Exception as e:
            logger.error(f"Failed to connect IMAP for {account_id}: {e}")
            return False
    
    def _close_connection(self, account_id: str):
        """Chiude una connessione esistente in modo sicuro"""
        if account_id in self._connections:
            try:
                self._connections[account_id].logout()
            except:
                pass
            try:
                self._connections[account_id].close()
            except:
                pass
            del self._connections[account_id]
    
    def _is_connection_alive(self, account_id: str) -> bool:
        """Verifica se una connessione IMAP è ancora attiva"""
        if account_id not in self._connections:
            return False
        
        try:
            # NOOP è un comando leggero per verificare la connessione
            status, _ = self._connections[account_id].noop()
            if status == 'OK':
                self._last_successful_op[account_id] = datetime.now()
                return True
            return False
        except Exception as e:
            logger.debug(f"Connection check failed for {account_id}: {e}")
            return False
    
    def _reconnect(self, account_id: str) -> bool:
        """Tenta di riconnettere un account"""
        if account_id not in self._credentials:
            logger.warning(f"No credentials stored for reconnection: {account_id}")
            return False
        
        creds = self._credentials[account_id]
        logger.info(f"Attempting to reconnect account: {account_id}")
        
        for attempt in range(MAX_RECONNECT_ATTEMPTS):
            if self.connect(account_id, creds['email'], creds['token']):
                logger.info(f"Reconnection successful for {account_id} (attempt {attempt + 1})")
                return True
            logger.warning(f"Reconnection attempt {attempt + 1}/{MAX_RECONNECT_ATTEMPTS} failed for {account_id}")
            # Breve pausa tra i tentativi
            import time
            time.sleep(2 ** attempt)  # Backoff esponenziale: 1s, 2s, 4s
        
        logger.error(f"All reconnection attempts failed for {account_id}")
        return False
    
    def ensure_connection(self, account_id: str) -> bool:
        """Assicura che la connessione sia attiva, riconnettendo se necessario"""
        if self._is_connection_alive(account_id):
            return True
        
        logger.warning(f"Connection lost for {account_id}, attempting reconnection...")
        return self._reconnect(account_id)
    
    def update_token(self, account_id: str, new_token: str):
        """Aggiorna il token OAuth per un account (chiamato dopo refresh)"""
        if account_id in self._credentials:
            self._credentials[account_id]['token'] = new_token
            logger.debug(f"Updated OAuth token for {account_id}")
    
    def disconnect(self, account_id: str):
        """Disconnette da un account"""
        self._close_connection(account_id)
        self._credentials.pop(account_id, None)
        self._last_successful_op.pop(account_id, None)
    
    def disconnect_all(self):
        """Disconnette da tutti gli account"""
        for account_id in list(self._connections.keys()):
            self.disconnect(account_id)
    
    def fetch_emails(self, account_id: str, mailbox: str = 'INBOX',
                     seen_message_ids: Optional[Set[str]] = None) -> Tuple[List[Dict], Set[str]]:
        """
        Recupera email con strategia: ultimi 7 giorni + tutte le non lette.
        
        Args:
            account_id: ID account
            mailbox: Casella da controllare
            seen_message_ids: Set di message_id già processati (per deduplicazione)
        
        Returns:
            Tuple (lista email, set message_id visti in questa sessione)
        """
        # Verifica/riconnetti la connessione prima di procedere
        if not self.ensure_connection(account_id):
            logger.error(f"Cannot connect to account: {account_id}")
            return [], set()
        
        if seen_message_ids is None:
            seen_message_ids = set()
        
        imap = self._connections[account_id]
        all_emails = []
        session_seen = set()
        
        try:
            # Seleziona mailbox
            status, _ = imap.select(mailbox, readonly=False)
            if status != 'OK':
                logger.error(f"Failed to select mailbox {mailbox}")
                return [], set()
            
            # 1. Fetch ultimi 7 giorni (lette e non lette)
            since_date = datetime.now() - timedelta(days=self.fetch_days)
            date_str = since_date.strftime('%d-%b-%Y')
            
            logger.info(f"Fetching emails since {date_str} for {account_id}")
            
            status, recent_ids = imap.search(None, f'(SINCE {date_str})')
            recent_msg_ids = recent_ids[0].split() if status == 'OK' and recent_ids[0] else []
            
            # 2. Fetch tutte le non lette (senza limite temporale)
            status, unread_ids = imap.search(None, '(UNSEEN)')
            unread_msg_ids = unread_ids[0].split() if status == 'OK' and unread_ids[0] else []
            
            # Combina e deduplica
            all_msg_ids = list(set(recent_msg_ids + unread_msg_ids))
            
            # Limita per evitare sovraccarico
            if len(all_msg_ids) > MAX_EMAILS_PER_FETCH:
                logger.warning(f"Limiting fetch from {len(all_msg_ids)} to {MAX_EMAILS_PER_FETCH}")
                # Priorità: non lette prima, poi recenti
                unread_set = set(unread_msg_ids)
                prioritized = [m for m in all_msg_ids if m in unread_set]
                prioritized += [m for m in all_msg_ids if m not in unread_set]
                all_msg_ids = prioritized[:MAX_EMAILS_PER_FETCH]
            
            logger.info(f"Found {len(recent_msg_ids)} recent + {len(unread_msg_ids)} unread = {len(all_msg_ids)} unique for {account_id}")
            
            # Marca operazione come successo
            self._last_successful_op[account_id] = datetime.now()
            
            for msg_id in all_msg_ids:
                email_data = self._fetch_email(imap, msg_id, account_id)
                if email_data:
                    message_id = email_data.get('message_id', '')
                    
                    # Deduplicazione
                    if message_id and message_id in seen_message_ids:
                        logger.debug(f"Skipping duplicate: {message_id[:30]}...")
                        continue
                    
                    if message_id:
                        session_seen.add(message_id)
                    
                    # Identifica tutti gli utenti destinatari
                    email_data['recipient_users'] = self._identify_recipient_users(email_data)
                    
                    all_emails.append(email_data)
            
            return all_emails, session_seen
        
        except (imaplib.IMAP4.abort, imaplib.IMAP4.error) as e:
            logger.warning(f"IMAP error for {account_id}, will reconnect on next attempt: {e}")
            # Forza disconnessione per triggherare riconnessione al prossimo giro
            self._close_connection(account_id)
            return [], set()
        except (socket.timeout, socket.error, ssl.SSLError) as e:
            logger.warning(f"Network error for {account_id}: {e}")
            self._close_connection(account_id)
            return [], set()
        except Exception as e:
            logger.error(f"Error fetching emails for {account_id}: {e}", exc_info=True)
            return [], set()
    
    def _identify_recipient_users(self, email_data: Dict) -> List[str]:
        """
        Identifica quali utenti del sistema sono destinatari di questa email.
        Usato per mostrare la stessa email a più utenti.
        """
        recipient_users = set()
        
        # Controlla To
        for addr in email_data.get('to', []):
            user_id = self.get_user_for_email(addr.get('email', ''))
            if user_id:
                recipient_users.add(user_id)
        
        # Controlla CC
        for addr in email_data.get('cc', []):
            user_id = self.get_user_for_email(addr.get('email', ''))
            if user_id:
                recipient_users.add(user_id)
        
        # L'account che l'ha scaricata è sempre incluso
        account_id = email_data.get('account_id')
        if account_id:
            recipient_users.add(account_id)
        
        return list(recipient_users)
    
    def _fetch_email(self, imap: imaplib.IMAP4_SSL, msg_id: bytes, 
                     account_id: str) -> Optional[Dict]:
        """Scarica e parsa una singola email"""
        try:
            status, data = imap.fetch(msg_id, '(RFC822 FLAGS)')
            if status != 'OK':
                return None
            
            raw_email = data[0][1]
            flags_data = data[0][0] if len(data[0]) > 0 else b''
            
            # Check if read
            is_read = b'\\Seen' in flags_data if isinstance(flags_data, bytes) else False
            
            msg = email.message_from_bytes(raw_email)
            
            # Parse headers
            message_id = msg.get('Message-ID', '')
            if not message_id:
                # Genera hash se manca Message-ID
                content = f"{msg.get('Subject', '')}{msg.get('Date', '')}{msg.get('From', '')}"
                message_id = f"<{hashlib.sha256(content.encode()).hexdigest()[:32]}@generated>"
            
            subject = self._decode_header(msg.get('Subject', ''))
            from_addr = self._parse_address(msg.get('From', ''))
            to_addrs = self._parse_addresses(msg.get('To', ''))
            cc_addrs = self._parse_addresses(msg.get('Cc', ''))
            date_str = msg.get('Date', '')
            
            # Parse date
            try:
                from email.utils import parsedate_to_datetime
                date = parsedate_to_datetime(date_str)
            except:
                date = datetime.now()
            
            # Extract body and attachments
            body_text = ''
            body_html = ''
            attachments = []
            
            if msg.is_multipart():
                for part in msg.walk():
                    content_type = part.get_content_type()
                    disposition = str(part.get('Content-Disposition', ''))
                    
                    if 'attachment' in disposition:
                        # Attachment
                        filename = part.get_filename()
                        if filename:
                            filename = self._decode_header(filename)
                            payload = part.get_payload(decode=True)
                            if payload:
                                attachments.append({
                                    'filename': filename,
                                    'data': base64.b64encode(payload).decode('utf-8'),
                                    'size': len(payload),
                                    'mime_type': content_type
                                })
                    elif content_type == 'text/plain' and not body_text:
                        payload = part.get_payload(decode=True)
                        if payload:
                            body_text = payload.decode('utf-8', errors='replace')
                    elif content_type == 'text/html' and not body_html:
                        payload = part.get_payload(decode=True)
                        if payload:
                            body_html = payload.decode('utf-8', errors='replace')
            else:
                # Not multipart
                payload = msg.get_payload(decode=True)
                if payload:
                    if msg.get_content_type() == 'text/html':
                        body_html = payload.decode('utf-8', errors='replace')
                    else:
                        body_text = payload.decode('utf-8', errors='replace')
            
            return {
                'message_id': message_id,
                'account_id': account_id,
                'subject': subject,
                'from': from_addr,
                'to': to_addrs,
                'cc': cc_addrs,
                'date': date.isoformat(),
                'body_text': body_text,
                'body_html': body_html,
                'attachments': attachments,
                'is_read': is_read,
                'direction': 'inbound',
                'imap_uid': msg_id.decode() if isinstance(msg_id, bytes) else str(msg_id)
            }
            
        except Exception as e:
            logger.error(f"Error parsing email {msg_id}: {e}")
            return None
    
    def mark_as_read(self, account_id: str, message_ids: List[str], mailbox: str = 'INBOX') -> int:
        """
        Marca email come lette su IMAP.
        
        Returns:
            Numero di email marcate
        """
        # Verifica/riconnetti la connessione
        if not self.ensure_connection(account_id):
            return 0
        
        imap = self._connections[account_id]
        marked = 0
        
        try:
            imap.select(mailbox, readonly=False)
            for msg_id in message_ids:
                # Cerca per Message-ID header
                status, data = imap.search(None, f'(HEADER Message-ID "{msg_id}")')
                if status == 'OK' and data[0]:
                    for uid in data[0].split():
                        imap.store(uid, '+FLAGS', '\\Seen')
                        marked += 1
            self._last_successful_op[account_id] = datetime.now()
        except (imaplib.IMAP4.abort, imaplib.IMAP4.error, socket.timeout, socket.error) as e:
            logger.warning(f"Connection error marking as read for {account_id}: {e}")
            self._close_connection(account_id)
        except Exception as e:
            logger.error(f"Error marking as read: {e}")
        
        return marked
    
    def mark_as_read_all_accounts(self, message_id: str) -> int:
        """
        Marca una email come letta su TUTTI gli account.
        Usato per email condivise tra più utenti.
        
        Returns:
            Numero totale di marcature
        """
        total_marked = 0
        for account_id in self._connections.keys():
            marked = self.mark_as_read(account_id, [message_id])
            total_marked += marked
        return total_marked
    
    def _decode_header(self, header: str) -> str:
        """Decodifica header email"""
        try:
            decoded = decode_header(header)
            result = ''
            for part, encoding in decoded:
                if isinstance(part, bytes):
                    result += part.decode(encoding or 'utf-8', errors='replace')
                else:
                    result += part
            return result
        except:
            return header
    
    def _parse_address(self, addr_str: str) -> Dict[str, str]:
        """Parsa un indirizzo email"""
        from email.utils import parseaddr
        name, email_addr = parseaddr(addr_str)
        return {'email': email_addr, 'name': name if name else None}
    
    def _parse_addresses(self, addr_str: str) -> List[Dict[str, str]]:
        """Parsa multipli indirizzi email"""
        if not addr_str:
            return []
        
        from email.utils import getaddresses
        addresses = getaddresses([addr_str])
        return [{'email': email_addr, 'name': name if name else None} 
                for name, email_addr in addresses]
