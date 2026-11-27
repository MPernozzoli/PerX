"""Tabelle della Regia e del profilo Chiari."""
from sqlalchemy import Boolean, Column, Date, DateTime, ForeignKey, Integer, JSON, Numeric, String, Text, UniqueConstraint
from sqlalchemy.sql import func

from app.core.database import Base


class TenantClaimState(Base):
    __tablename__ = "tenant_claim_states"
    __table_args__ = (UniqueConstraint("tenant_id", "code", name="uq_tenant_claim_states_code"),)

    id = Column(String, primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True)
    code = Column(String, nullable=False)
    label = Column(String, nullable=False)
    description = Column(Text, nullable=True)
    actor = Column(String, nullable=True)
    is_meta = Column(Boolean, nullable=False, default=False)
    sort_order = Column(Integer, nullable=False, default=0)
    active = Column(Boolean, nullable=False, default=True)


class ClaimWorkflow(Base):
    __tablename__ = "claim_workflows"

    claim_id = Column(String, ForeignKey("claims.id", ondelete="CASCADE"), primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True)
    salesforce_id = Column(String, nullable=True, index=True)
    company_claim_number = Column(String, nullable=True)
    ispettorato = Column(String, nullable=True)
    liquidatore = Column(String, nullable=True)
    salesforce_status = Column(String, nullable=True)
    closed_on = Column(String, nullable=True)
    outcome = Column(String, nullable=True)
    expected_close_on = Column(String, nullable=True)
    passages_json = Column(JSON, nullable=True)
    checks_json = Column(JSON, nullable=True)
    reclaim_model = Column(String, nullable=True)
    manual_state_code = Column(String, nullable=True)
    manual_state_at = Column(DateTime(timezone=True), nullable=True)


class ClaimGroup(Base):
    __tablename__ = "claim_groups"
    __table_args__ = (UniqueConstraint("tenant_id", "kind", "external_key", name="uq_claim_groups_key"),)

    id = Column(String, primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True)
    kind = Column(String, nullable=False)
    external_key = Column(String, nullable=False)
    reason = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class ClaimGroupMember(Base):
    __tablename__ = "claim_group_members"
    __table_args__ = (UniqueConstraint("group_id", "claim_id", name="uq_claim_group_member"),)

    id = Column(String, primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True)
    group_id = Column(String, ForeignKey("claim_groups.id", ondelete="CASCADE"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id", ondelete="CASCADE"), nullable=False, index=True)


class ClaimEstimateRevision(Base):
    __tablename__ = "claim_estimate_revisions"
    __table_args__ = (UniqueConstraint("claim_id", "revision_number", name="uq_claim_estimate_revision"),)

    id = Column(String, primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id", ondelete="CASCADE"), nullable=False, index=True)
    revision_number = Column(Integer, nullable=False)
    input_json = Column(JSON, nullable=False)
    calculation_json = Column(JSON, nullable=False)
    calculation_hash = Column(String, nullable=True)
    economic_hash = Column(String, nullable=True, index=True)
    liquidabile = Column(Numeric(12, 2), nullable=True)
    approved_at = Column(DateTime(timezone=True), nullable=True)
    approved_by_user_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    inherited_from_revision_id = Column(String, ForeignKey("claim_estimate_revisions.id", ondelete="SET NULL"), nullable=True)
    superseded_at = Column(DateTime(timezone=True), nullable=True)
    amount_exception_reason = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class ClaimAtto(Base):
    __tablename__ = "claim_atti"

    id = Column(String, primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id", ondelete="CASCADE"), nullable=False, index=True)
    kind = Column(String, nullable=False)
    amount = Column(Numeric(12, 2), nullable=True)
    sent_at = Column(DateTime(timezone=True), nullable=True)
    signed_at = Column(DateTime(timezone=True), nullable=True)
    iban = Column(String, nullable=True)
    iban_verified = Column(Boolean, nullable=False, default=False)
    beneficiary = Column(String, nullable=True)
    fingerprint = Column(String, nullable=True)
    metadata_json = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class ClaimQuestion(Base):
    __tablename__ = "claim_questions"

    id = Column(String, primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True)
    claim_id = Column(String, ForeignKey("claims.id", ondelete="CASCADE"), nullable=True, index=True)
    job_id = Column(String, ForeignKey("process_jobs.id", ondelete="SET NULL"), nullable=True, index=True)
    question_type = Column(String, nullable=False)
    raised_level = Column(String, nullable=True)
    description = Column(Text, nullable=False)
    evidence_json = Column(JSON, nullable=True)
    options_json = Column(JSON, nullable=True)
    recommendation = Column(Text, nullable=True)
    answer_text = Column(Text, nullable=True)
    answer_scope = Column(String, nullable=True)
    answered_by_user_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    answered_at = Column(DateTime(timezone=True), nullable=True)
    outcome = Column(String, nullable=True)
    status = Column(String, nullable=False, default="aperta", index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class TenantRule(Base):
    __tablename__ = "tenant_rules"

    id = Column(String, primary_key=True)
    tenant_id = Column(String, ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False, index=True)
    body = Column(Text, nullable=False)
    rule_type = Column(String, nullable=False)
    scope = Column(String, nullable=True)
    author = Column(String, nullable=True)
    origin_label = Column(String, nullable=True)
    originated_on = Column(Date, nullable=True)
    origin_claim_ref = Column(String, nullable=True)
    status = Column(String, nullable=False, default="proposta", index=True)
    version = Column(Integer, nullable=False, default=1)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
