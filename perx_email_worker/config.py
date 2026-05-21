"""
Configuration for PerX Email Worker
"""
import os
import json
from pathlib import Path
from typing import List, Dict, Any
from dotenv import load_dotenv

load_dotenv()

# Hub configuration
HUB_URL = os.getenv('HUB_URL', 'http://localhost:8080')
CLOUD_API_URL = os.getenv('CLOUD_API_URL', HUB_URL)
LOCAL_AI_WORKER_ID = os.getenv('LOCAL_AI_WORKER_ID', 'mac-mini-local-ai')
LOCAL_AI_WORKER_SHARED_SECRET = os.getenv('LOCAL_AI_WORKER_SHARED_SECRET', '')
CLOUD_JOB_POLL_INTERVAL = int(os.getenv('CLOUD_JOB_POLL_INTERVAL', '5'))
PROCESS_JOB_BATCH_SIZE = int(os.getenv('PROCESS_JOB_BATCH_SIZE', '3'))
PROCESS_JOB_LEASE_SECONDS = int(os.getenv('PROCESS_JOB_LEASE_SECONDS', '300'))

# Polling intervals
IMAP_POLL_INTERVAL = int(os.getenv('IMAP_POLL_INTERVAL', '60'))  # seconds
SCHEDULED_CHECK_INTERVAL = int(os.getenv('SCHEDULED_CHECK_INTERVAL', '30'))  # seconds

# Email fetch settings
FETCH_DAYS = int(os.getenv('FETCH_DAYS', '7'))  # Scarica email degli ultimi N giorni + tutte le non lette

# IMAP/SMTP settings (will be overridden by per-account settings)
DEFAULT_IMAP_HOST = 'imap.gmail.com'
DEFAULT_IMAP_PORT = 993
DEFAULT_SMTP_HOST = 'smtp.gmail.com'
DEFAULT_SMTP_PORT = 587

# OAuth2 settings (for Gmail)
GOOGLE_CLIENT_ID = os.getenv('GOOGLE_CLIENT_ID', '')
GOOGLE_CLIENT_SECRET = os.getenv('GOOGLE_CLIENT_SECRET', '')

# Logging
LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
LOG_FILE = os.getenv('LOG_FILE', 'logs/email_worker.log')

# Accounts configuration file path
ACCOUNTS_FILE = os.getenv('ACCOUNTS_FILE', 'accounts.json')


def load_accounts() -> List[Dict[str, Any]]:
    """
    Carica gli account email dal file di configurazione.
    
    Formato accounts.json:
    [
        {
            "user_id": "massimo.pernozzoli",
            "email": "massimo.pernozzoli@dominio.it",
            "oauth_token_file": "/path/to/token.json",
            "enabled": true
        }
    ]
    
    user_id è la local-part dell'email (convenzione ID utente univoco).
    oauth_token_file punta al file con il refresh token OAuth2.
    """
    accounts_path = Path(ACCOUNTS_FILE)
    
    if not accounts_path.exists():
        return []
    
    try:
        with open(accounts_path, 'r', encoding='utf-8') as f:
            accounts = json.load(f)
            
        # Filtra solo account abilitati
        enabled_accounts = [a for a in accounts if a.get('enabled', True)]
        
        # Carica token OAuth da file per ogni account
        for account in enabled_accounts:
            token_file = account.get('oauth_token_file')
            if token_file and Path(token_file).exists():
                try:
                    with open(token_file, 'r', encoding='utf-8') as tf:
                        token_data = json.load(tf)
                        account['oauth_token'] = token_data.get('access_token')
                        account['refresh_token'] = token_data.get('refresh_token')
                except Exception as e:
                    print(f"[Config] Warning: Failed to load token for {account.get('user_id')}: {e}")
        
        return enabled_accounts
        
    except Exception as e:
        print(f"[Config] Error loading accounts: {e}")
        return []
