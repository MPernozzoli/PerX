"""
Log immutabile delle esecuzioni AI per il flusso sinistri.

Il client (iOS, PerXHub) chiama POST /api/v1/ai/analysis-runs a ogni esecuzione
di fase, passando: quale prompt_version_id ha usato, quale provider
(local_mlx, openai, anthropic, …), quale modello, latenza, esito.

Serve per:
- audit: ricostruire con quale prompt una vecchia analisi è stata prodotta
- osservabilità: capire quante volte cade il fallback locale -> cloud
- tuning policy: vedere se le fasi marcate prefer_local stanno effettivamente
  girando in locale o se cadono troppo spesso in cloud
"""
from sqlalchemy import Column, String, Text, Integer, DateTime, ForeignKey, Index
from sqlalchemy.sql import func

from app.core.database import Base


RUN_STATUSES = ("success", "error", "fallback")


class AIAnalysisRun(Base):
    __tablename__ = "ai_analysis_runs"

    id = Column(String, primary_key=True, index=True)
    tenant_id = Column(String, ForeignKey("tenants.id"), nullable=True, index=True)
    sinistro_ref = Column(String, nullable=True, index=True)

    phase = Column(String, nullable=False, index=True)
    prompt_key = Column(String, nullable=False)
    prompt_version_id = Column(String, nullable=False)

    provider_used = Column(String, nullable=False)  # local_mlx | openai | anthropic | ...
    model_name = Column(String, nullable=True)
    mode_applied = Column(String, nullable=False)  # uno tra ROUTING_MODES
    trigger = Column(String, nullable=False)  # uno tra ROUTING_TRIGGERS

    latency_ms = Column(Integer, nullable=True)
    input_token_count = Column(Integer, nullable=True)
    output_token_count = Column(Integer, nullable=True)

    status = Column(String, nullable=False)  # uno tra RUN_STATUSES
    error_message = Column(Text, nullable=True)

    client_id = Column(String, nullable=True)  # device/host identifier (iPad, Mac mini, …)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False, index=True)

    __table_args__ = (
        Index("ix_ai_runs_tenant_phase_created", "tenant_id", "phase", "created_at"),
    )
