"""
Token Management Service
Gestione sicura dei token OAuth2 per Gmail.
"""
import os
import json
import logging
import hashlib
import requests
from datetime import datetime, timedelta
from typing import Dict, Optional, Tuple
from threading import Lock
from cryptography.fernet import Fernet
from pathlib import Path

logger = logging.getLogger(__name__)

# Configurazione OAuth2 Google
# IMPORTANTE: Client ID e Secret DEVONO essere configurati via env vars
GOOGLE_CLIENT_ID = os.getenv('GOOGLE_CLIENT_ID')
GOOGLE_CLIENT_SECRET = os.getenv('GOOGLE_CLIENT_SECRET')
TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
USERINFO_ENDPOINT = "https://www.googleapis.com/oauth2/v2/userinfo"

if not GOOGLE_CLIENT_ID or not GOOGLE_CLIENT_SECRET:
    logger.warning("⚠️ GOOGLE_CLIENT_ID e/o GOOGLE_CLIENT_SECRET non configurati! OAuth2 non funzionerà.")


class TokenService:
    """
    Gestione token OAuth2 per multipli utenti.
    
    Funzionalità:
    - Storage criptato dei refresh_token
    - Refresh automatico degli access_token
    - Validazione token
    - Supporto multi-utente
    """
    
    def __init__(self, storage_path: str = "data/tokens"):
        self.storage_path = Path(storage_path)
        self.storage_path.mkdir(parents=True, exist_ok=True)
        
        # Cache in memoria degli access_token
        self._access_tokens: Dict[str, Tuple[str, datetime]] = {}  # user_id -> (token, expiry)
        self._lock = Lock()
        
        # Chiave di cifratura (in produzione, usare un secret manager)
        self._encryption_key = self._get_or_create_encryption_key()
        self._fernet = Fernet(self._encryption_key)
    
    def _get_or_create_encryption_key(self) -> bytes:
        """Ottiene o crea la chiave di cifratura"""
        key_file = self.storage_path / ".encryption_key"
        
        if key_file.exists():
            return key_file.read_bytes()
        
        # Genera nuova chiave
        key = Fernet.generate_key()
        key_file.write_bytes(key)
        # Proteggi il file
        os.chmod(key_file, 0o600)
        return key
    
    def _get_user_file(self, user_id: str) -> Path:
        """Path del file token per un utente"""
        # Hash dell'user_id per sicurezza del filename
        safe_id = hashlib.sha256(user_id.encode()).hexdigest()[:16]
        return self.storage_path / f"user_{safe_id}.enc"
    
    # ========== Storage Token ==========
    
    def store_refresh_token(self, user_id: str, email: str, refresh_token: str) -> bool:
        """
        Salva il refresh_token per un utente.
        Chiamato dall'Hub quando il client invia i token.
        """
        try:
            data = {
                'user_id': user_id,
                'email': email,
                'refresh_token': refresh_token,
                'stored_at': datetime.now().isoformat()
            }
            
            encrypted = self._fernet.encrypt(json.dumps(data).encode())
            
            with self._lock:
                user_file = self._get_user_file(user_id)
                user_file.write_bytes(encrypted)
            
            logger.info(f"Stored refresh token for user: {user_id}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to store token for {user_id}: {e}")
            return False
    
    def get_refresh_token(self, user_id: str) -> Optional[str]:
        """Recupera il refresh_token di un utente"""
        try:
            user_file = self._get_user_file(user_id)
            if not user_file.exists():
                return None
            
            encrypted = user_file.read_bytes()
            decrypted = self._fernet.decrypt(encrypted)
            data = json.loads(decrypted.decode())
            
            return data.get('refresh_token')
            
        except Exception as e:
            logger.error(f"Failed to load token for {user_id}: {e}")
            return None
    
    def get_user_email(self, user_id: str) -> Optional[str]:
        """Recupera l'email associata a un user_id"""
        try:
            user_file = self._get_user_file(user_id)
            if not user_file.exists():
                return None
            
            encrypted = user_file.read_bytes()
            decrypted = self._fernet.decrypt(encrypted)
            data = json.loads(decrypted.decode())
            
            return data.get('email')
            
        except Exception as e:
            logger.error(f"Failed to load email for {user_id}: {e}")
            return None
    
    def delete_token(self, user_id: str) -> bool:
        """Elimina i token di un utente"""
        try:
            user_file = self._get_user_file(user_id)
            if user_file.exists():
                user_file.unlink()
            
            # Rimuovi dalla cache
            with self._lock:
                self._access_tokens.pop(user_id, None)
            
            logger.info(f"Deleted token for user: {user_id}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to delete token for {user_id}: {e}")
            return False
    
    def has_valid_token(self, user_id: str) -> bool:
        """Verifica se un utente ha un token valido"""
        return self.get_refresh_token(user_id) is not None
    
    def list_users(self) -> list:
        """Lista tutti gli utenti con token salvati"""
        users = []
        for file in self.storage_path.glob("user_*.enc"):
            try:
                encrypted = file.read_bytes()
                decrypted = self._fernet.decrypt(encrypted)
                data = json.loads(decrypted.decode())
                users.append({
                    'user_id': data.get('user_id'),
                    'email': data.get('email'),
                    'stored_at': data.get('stored_at')
                })
            except:
                continue
        return users
    
    # ========== Access Token Management ==========
    
    def get_access_token(self, user_id: str) -> Optional[str]:
        """
        Ottiene un access_token valido per un utente.
        Usa la cache se disponibile, altrimenti fa refresh.
        """
        with self._lock:
            # Check cache
            if user_id in self._access_tokens:
                token, expiry = self._access_tokens[user_id]
                # Valido se scade tra più di 5 minuti
                if expiry > datetime.now() + timedelta(minutes=5):
                    return token
        
        # Refresh needed
        return self.refresh_access_token(user_id)
    
    def refresh_access_token(self, user_id: str) -> Optional[str]:
        """Esegue il refresh dell'access_token"""
        refresh_token = self.get_refresh_token(user_id)
        if not refresh_token:
            logger.warning(f"No refresh token for user: {user_id}")
            return None
        
        try:
            response = requests.post(TOKEN_ENDPOINT, data={
                'client_id': GOOGLE_CLIENT_ID,
                'client_secret': GOOGLE_CLIENT_SECRET,
                'refresh_token': refresh_token,
                'grant_type': 'refresh_token'
            }, timeout=30)
            
            if response.status_code != 200:
                error = response.json().get('error', 'Unknown')
                logger.error(f"Token refresh failed for {user_id}: {error}")
                
                # Se il refresh token è invalido, rimuovilo
                if error in ['invalid_grant', 'invalid_token']:
                    self.delete_token(user_id)
                
                return None
            
            data = response.json()
            access_token = data['access_token']
            expires_in = data.get('expires_in', 3600)
            expiry = datetime.now() + timedelta(seconds=expires_in)
            
            # Salva in cache
            with self._lock:
                self._access_tokens[user_id] = (access_token, expiry)
            
            logger.debug(f"Refreshed access token for {user_id}, expires in {expires_in}s")
            return access_token
            
        except Exception as e:
            logger.error(f"Token refresh error for {user_id}: {e}")
            return None
    
    def validate_token(self, user_id: str) -> Tuple[bool, Optional[str]]:
        """
        Valida un token e restituisce lo stato.
        
        Returns:
            (is_valid, email) - email è None se il token non è valido
        """
        access_token = self.get_access_token(user_id)
        if not access_token:
            return False, None
        
        try:
            response = requests.get(
                USERINFO_ENDPOINT,
                headers={'Authorization': f'Bearer {access_token}'},
                timeout=10
            )
            
            if response.status_code == 200:
                data = response.json()
                return True, data.get('email')
            else:
                logger.warning(f"Token validation failed for {user_id}: {response.status_code}")
                return False, None
                
        except Exception as e:
            logger.error(f"Token validation error for {user_id}: {e}")
            return False, None


# Singleton instance
_token_service: Optional[TokenService] = None


def get_token_service() -> TokenService:
    """Ottiene l'istanza singleton del TokenService"""
    global _token_service
    if _token_service is None:
        _token_service = TokenService()
    return _token_service
