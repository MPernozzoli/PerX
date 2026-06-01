"""
Portal notification preferences — vivono sull'Actor così le scelte valgono
cross-sinistro automaticamente (presenti, passati e futuri).

Quando un assicurato apre un nuovo sinistro mesi dopo, le sue preferenze
notifiche restano quelle che aveva già impostato.
"""
from sqlalchemy import Boolean, Column, DateTime, ForeignKey, String, Time
from sqlalchemy.sql import func

from app.core.database import Base


class PortalNotificationPrefs(Base):
    __tablename__ = "portal_notification_prefs"

    # PK = actor_id (1:1 con Actor): la riga viene creata lazy alla prima
    # apertura della pagina impostazioni o al primo update.
    actor_id = Column(
        String,
        ForeignKey("actors.id", ondelete="CASCADE"),
        primary_key=True,
    )
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)

    # Canali abilitati
    channel_push = Column(Boolean, nullable=False, default=False)
    channel_email = Column(Boolean, nullable=False, default=True)
    channel_whatsapp = Column(Boolean, nullable=False, default=False)
    channel_sms = Column(Boolean, nullable=False, default=False)

    # Canale preferito tra quelli abilitati: 'email' | 'whatsapp' | 'sms' | 'push'
    preferred_channel = Column(String, nullable=False, default="email")

    # Telefonate dal perito
    allow_phone_calls = Column(Boolean, nullable=False, default=True)
    # Fascia oraria preferita per essere chiamato (HH:MM)
    call_window_start = Column(Time, nullable=True)
    call_window_end = Column(Time, nullable=True)

    # Quiet hours globali: niente push/SMS in questa fascia
    quiet_hours_start = Column(Time, nullable=True)
    quiet_hours_end = Column(Time, nullable=True)

    # Email aggiuntiva di tutti i documenti generati (oltre alla notifica)
    documents_via_email = Column(Boolean, nullable=False, default=False)

    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
