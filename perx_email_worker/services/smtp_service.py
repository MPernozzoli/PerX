"""
SMTP Service for sending emails
"""
import smtplib
import base64
import logging
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email import encoders
from typing import List, Dict, Optional

logger = logging.getLogger(__name__)


class SMTPService:
    """
    Servizio SMTP per invio email.
    Supporta OAuth2 per Gmail.
    """
    
    def __init__(self, hub_url: str):
        self.hub_url = hub_url.rstrip('/')
    
    def send_email(
        self,
        account_id: str,
        email_address: str,
        oauth_token: str,
        to: List[str],
        subject: str,
        body_html: str,
        body_text: Optional[str] = None,
        cc: Optional[List[str]] = None,
        attachments: Optional[List[Dict]] = None
    ) -> Dict:
        """
        Invia email tramite Gmail SMTP.
        
        Args:
            account_id: ID account
            email_address: Indirizzo mittente
            oauth_token: OAuth2 token
            to: Lista destinatari
            subject: Oggetto
            body_html: Corpo HTML
            body_text: Corpo text (opzionale)
            cc: Lista CC (opzionale)
            attachments: Lista allegati [{filename, data (base64), mime_type}]
        
        Returns:
            Dict con esito {success, message_id, error}
        """
        try:
            # Crea messaggio
            msg = MIMEMultipart('alternative')
            msg['From'] = email_address
            msg['To'] = ', '.join(to)
            msg['Subject'] = subject
            
            if cc:
                msg['Cc'] = ', '.join(cc)
            
            # Body
            if body_text:
                msg.attach(MIMEText(body_text, 'plain', 'utf-8'))
            msg.attach(MIMEText(body_html, 'html', 'utf-8'))
            
            # Attachments
            if attachments:
                for att in attachments:
                    data = base64.b64decode(att['data'])
                    filename = att.get('filename', 'attachment')
                    mime_type = att.get('mime_type', 'application/octet-stream')
                    
                    maintype, subtype = mime_type.split('/', 1) if '/' in mime_type else ('application', 'octet-stream')
                    
                    part = MIMEBase(maintype, subtype)
                    part.set_payload(data)
                    encoders.encode_base64(part)
                    part.add_header('Content-Disposition', f'attachment; filename="{filename}"')
                    msg.attach(part)
            
            # Connessione SMTP con OAuth2
            smtp = smtplib.SMTP('smtp.gmail.com', 587)
            smtp.starttls()
            
            # OAuth2 authentication
            auth_string = f'user={email_address}\x01auth=Bearer {oauth_token}\x01\x01'
            smtp.docmd('AUTH', 'XOAUTH2 ' + base64.b64encode(auth_string.encode()).decode())
            
            # Destinatari effettivi
            recipients = to + (cc or [])
            
            # Invio
            smtp.sendmail(email_address, recipients, msg.as_string())
            smtp.quit()
            
            message_id = msg.get('Message-ID', '')
            logger.info(f"Email sent successfully: {subject} -> {to}")
            
            return {
                'success': True,
                'message_id': message_id,
                'error': None
            }
            
        except Exception as e:
            logger.error(f"Failed to send email: {e}")
            return {
                'success': False,
                'message_id': None,
                'error': str(e)
            }
    
    def send_scheduled(self, scheduled_email: Dict, oauth_token: str) -> Dict:
        """Invia email programmata"""
        return self.send_email(
            account_id=scheduled_email.get('accountId', ''),
            email_address=scheduled_email.get('accountEmail', ''),
            oauth_token=oauth_token,
            to=scheduled_email.get('to', []),
            subject=scheduled_email.get('subject', ''),
            body_html=scheduled_email.get('body', ''),
            cc=scheduled_email.get('cc'),
            attachments=scheduled_email.get('attachments')
        )
