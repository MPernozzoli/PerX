"""Schemi della Regia."""
from datetime import datetime
from decimal import Decimal
from typing import Any

from pydantic import BaseModel, Field


class RegiaProfileResponse(BaseModel):
    tenant_id: str
    tenant_slug: str
    workflow_profile: str
    single_operator: bool
    capabilities: dict[str, bool]


class TenantStateResponse(BaseModel):
    code: str
    label: str
    description: str | None = None
    actor: str | None = None
    is_meta: bool
    sort_order: int


class StateChangeRequest(BaseModel):
    code: str
    source: str = "perito"
    job_id: str | None = None


class RevisionCreateRequest(BaseModel):
    revision_number: int = Field(ge=1)
    input_json: dict[str, Any]
    calculation_json: dict[str, Any]
    amount_exception_reason: str | None = None


class RevisionResponse(BaseModel):
    id: str
    claim_id: str
    revision_number: int
    economic_hash: str | None
    liquidabile: Decimal | None
    approved_at: datetime | None
    inherited_from_revision_id: str | None
    amount_exception_reason: str | None

    model_config = {"from_attributes": True}


class QuestionCreateRequest(BaseModel):
    claim_id: str | None = None
    job_id: str | None = None
    question_type: str
    description: str
    raised_level: str | None = None
    evidence: dict[str, Any] | list[Any] | None = None
    options: list[Any] | None = None
    recommendation: str | None = None


class QuestionAnswerRequest(BaseModel):
    answer_text: str = Field(min_length=1)
    scope: str


class QuestionResponse(BaseModel):
    id: str
    claim_id: str | None
    question_type: str
    raised_level: str | None
    description: str
    recommendation: str | None
    answer_text: str | None
    answer_scope: str | None
    outcome: str | None
    status: str
    created_at: datetime

    model_config = {"from_attributes": True}


class RuleResponse(BaseModel):
    id: str
    body: str
    rule_type: str
    author: str | None
    origin_label: str | None
    status: str
    version: int

    model_config = {"from_attributes": True}


class JobCreateRequest(BaseModel):
    claim_id: str
    job_type: str
    phase: str
    resource: str
    model_level: str | None = None
    input_json: dict[str, Any] = Field(default_factory=dict)


class JobResponse(BaseModel):
    id: str
    claim_id: str | None
    job_type: str
    phase: str | None
    resource: str | None
    model_level: str | None
    status: str
    outcome: str | None

    model_config = {"from_attributes": True}


class SignedIbanRequest(BaseModel):
    iban: str
    beneficiary: str | None = None
    amount: Decimal | None = None
