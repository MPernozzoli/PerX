"""
Server-side claim complexity and priority scoring.

Replicates the AssignmentPlannerService.swift formula so the score is
authoritative on the server and not only computed inside the iOS/macOS clients.

Complexity formula (mirrors Swift):
  base = 1.0
  +0.35  if sopralluogo
  +0.15  if giustificativi
  +0.25  if oltre_dieci_beni
  +0.35  if richiesta > 10 000 €
  ai_contribution  (float added by photo analysis, 0.0–0.5)
  final = max(base + ai_contribution, 0.5)

Label thresholds (4 equal bands across 0.5–2.1 range):
  < 1.20  → bassa
  < 1.50  → media
  < 1.80  → alta
  ≥ 1.80  → molto_alta

Priority formula:
  base = 1.0
  +0.35  if richiesta > 5 000 €
  +0.25  if liquidato > 5 000 €
  +0.20  if sopralluogo
  +0.15  if stato_corrente == in_attesa_assegnazione
  +age_bonus  min((giorni_da_incarico / 10), 0.5)
  ai_contribution  (float added by photo analysis, 0.0–0.5)
"""
from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
from typing import Optional

from app.core.claim_status import ClaimStatus
from app.models.claim import Claim


COMPLEXITY_THRESHOLDS = [
    (1.20, "bassa"),
    (1.50, "media"),
    (1.80, "alta"),
    (float("inf"), "molto_alta"),
]

LABEL_TO_DISPLAY = {
    "bassa": "Bassa",
    "media": "Media",
    "alta": "Alta",
    "molto_alta": "Molto Alta",
}


def compute_complexity_score(
    claim: Claim,
    ai_contribution: float = 0.0,
) -> tuple[float, str]:
    """
    Returns (numeric_score, label) for claim complexity.

    ai_contribution is the AI-derived additive term from photo analysis
    (the worker emits complexity_ai_contribution in its result_json).
    """
    score = 1.0

    if claim.sopralluogo:
        score += 0.35
    if claim.giustificativi:
        score += 0.15
    if claim.oltre_dieci_beni:
        score += 0.25

    richiesta = _to_float(claim.richiesta)
    if richiesta is not None and richiesta > 10_000:
        score += 0.35

    score += max(0.0, float(ai_contribution))
    score = max(round(score, 4), 0.5)

    label = _score_to_label(score)
    return score, label


def compute_priority_score(
    claim: Claim,
    ai_contribution: float = 0.0,
) -> tuple[float, int]:
    """
    Returns (raw_score, normalized_0_10) for claim priority.
    """
    score = 1.0

    richiesta = _to_float(claim.richiesta)
    if richiesta is not None and richiesta > 5_000:
        score += 0.35

    liquidato = _to_float(claim.liquidato)
    if liquidato is not None and liquidato > 5_000:
        score += 0.25

    if claim.sopralluogo:
        score += 0.20

    if claim.stato_corrente == ClaimStatus.IN_ATTESA_ASSEGNAZIONE.value:
        score += 0.15

    if claim.data_incarico:
        now = datetime.now(timezone.utc)
        ref = claim.data_incarico
        if ref.tzinfo is None:
            ref = ref.replace(tzinfo=timezone.utc)
        age_days = max((now - ref).total_seconds() / 86_400, 0)
        score += min(age_days / 10.0, 0.5)

    score += max(0.0, float(ai_contribution))
    score = round(score, 4)

    # Normalize to 0-10 integer: max theoretical score ~2.75, map linearly
    normalized = int(round(min(score / 2.75, 1.0) * 10))
    return score, normalized


def _score_to_label(score: float) -> str:
    for threshold, label in COMPLEXITY_THRESHOLDS:
        if score < threshold:
            return label
    return "molto_alta"


def _to_float(value) -> Optional[float]:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None
