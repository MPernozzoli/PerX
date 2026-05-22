"""
AI photo analysis results for a portal document-collection submission.

Maps to the client-side PerxiaAnalisi + PerxiaBene CoreData entities so the
same data is available server-side without being tied to a running iOS/macOS client.
"""
from sqlalchemy import Column, DateTime, ForeignKey, Integer, JSON, Numeric, String
from sqlalchemy.sql import func

from app.core.database import Base


class ClaimPhotoAnalysis(Base):
    __tablename__ = "claim_photo_analyses"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id"), nullable=False, index=True)
    process_job_id = Column(String, ForeignKey("process_jobs.id"), nullable=True, index=True)
    submission_id = Column(String, nullable=True)
    status = Column(String, nullable=False, default="pending")

    # Provider / model metadata
    analysis_provider = Column(String, nullable=True)   # local_multimodal | cloud_openai | cloud_claude
    model = Column(String, nullable=True)

    # Scoring — numeric values so the server can recalculate labels
    complexity_base_score = Column(Numeric(6, 4), nullable=True)   # claim fields only
    complexity_ai_contribution = Column(Numeric(6, 4), nullable=True)  # AI-derived additive
    complexity_score = Column(Numeric(6, 4), nullable=True)         # base + ai_contribution
    complessita = Column(String, nullable=True)                     # derived label: bassa/media/alta/molto_alta

    priority_base_score = Column(Numeric(6, 4), nullable=True)
    priority_ai_contribution = Column(Numeric(6, 4), nullable=True)
    priority_score = Column(Numeric(6, 4), nullable=True)
    ai_priority = Column(Integer, nullable=True)                    # normalized 0-10

    analysis_confidence = Column(Numeric(4, 3), nullable=True)

    # PerxiaAnalisi equivalent
    relazione_complessiva = Column(String, nullable=True)

    # PerxiaBene array — each element mirrors the CoreData entity fields
    # Keys per bene: ordine, tipo_bene, foto_associate, tipologia, componenti, modello,
    #   anno, osservazioni_visive, valutazione_test, compatibilita_garanzia,
    #   compatibilita_danno, stima_economica, note_aggiuntive,
    #   certezza_tipologia, certezza_modello, certezza_anno, certezza_osservazioni,
    #   certezza_test, certezza_compatibilita, certezza_stima,
    #   componenti_dettaglio (list of same structure for sub-components)
    beni_json = Column(JSON, nullable=True)

    raw_result_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    completed_at = Column(DateTime(timezone=True), nullable=True)
