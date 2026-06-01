"""
Policy di routing tra esecuzione AI locale (MLX su client) e cloud.

Chiave: (tenant_id, phase, trigger). `tenant_id IS NULL` = default globale.

`phase` identifica una fase del flusso (es. "sinistri.tagging",
"sinistri.fase1_approfondita", "sinistri.relazione"), allineata con la `key`
dei prompt template.

`trigger` distingue *come* parte l'esecuzione:
- user_initiated  -> l'utente preme un bottone in UI (analizza, classifica…).
                     Sulle immagini di default preferiamo cloud per velocità.
- background      -> processo automatico (scansione foto da mail/WhatsApp,
                     job notturni). Di default preferiamo locale per non
                     bruciare budget cloud su lavoro non urgente.
- regenerate      -> l'utente ha rifiutato la risposta locale e chiede di
                     riprovare. Default cloud_only (assumiamo il locale non
                     sia stato soddisfacente).

`mode`:
- local_only    -> esegui sempre in locale; se il provider locale non risponde, errore
- prefer_local  -> prova locale, fallback cloud se non disponibile / unsupported / output malformato
- prefer_cloud  -> prova cloud, fallback locale se cloud non disponibile
- cloud_only    -> esegui sempre in cloud

NOTA cluster LAN (futuro): quando introdurremo lo smistamento dinamico tra
client nella stessa rete, lo schema NON cambia. La policy continuerà a dire
"preferenza locale"; sarà il router lato client a decidere se "locale"
significa questo device, un peer LAN scoperto via Bonjour, o l'Hub Mac mini.
Non aggiungere colonne qui per il clustering — va sul lato client.
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.sql import func

from app.core.database import Base


ROUTING_MODES = ("local_only", "prefer_local", "prefer_cloud", "cloud_only")
ROUTING_TRIGGERS = ("user_initiated", "background", "regenerate")


class AIRoutingPolicy(Base):
    __tablename__ = "ai_routing_policy"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=True, index=True)

    phase = Column(String, nullable=False, index=True)
    trigger = Column(String, nullable=False, index=True)
    mode = Column(String, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
    updated_by_user_id = Column(String, ForeignKey("users.id"), nullable=True)

    __table_args__ = (
        UniqueConstraint("tenant_id", "phase", "trigger", name="uq_ai_routing_tenant_phase_trigger"),
    )
