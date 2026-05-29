"""
Bignami policy summary routes.
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import or_, select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.claim import Claim
from app.models.user import User

router = APIRouter()


class BignamiSectionSummary(BaseModel):
    party: str | None = None
    title: str | None = None
    definition: str | None = None
    value_type: str | None = None
    primo_rischio_value: str | None = None
    deroga_percentage: float | None = None
    determinazione: list[str] = Field(default_factory=list)
    exclusions: list[str] = Field(default_factory=list)
    notes: list[str] = Field(default_factory=list)
    page_reference: str | None = None
    article_number: str | None = None


class BignamiCoverageItemSummary(BaseModel):
    guarantee_name: str
    guarantee_group: str | None = None
    description: str | None = None
    value_type: str | None = None
    maximum_value: str | None = None
    deductible_value: str | None = None
    guarantee_exclusions: list[str] = Field(default_factory=list)
    common_exclusions: list[str] = Field(default_factory=list)
    page_reference: str | None = None
    article_number: str | None = None


class BignamiCommonLimitSummary(BaseModel):
    label: str
    scope: str | None = None
    value: str | None = None
    on_frontespizio: bool = False
    page_reference: str | None = None
    article_number: str | None = None


class BignamiSummaryResponse(BaseModel):
    matched: bool
    query: dict[str, str | None] = Field(default_factory=dict)
    company_name: str | None = None
    company_code: str | None = None
    policy_name: str | None = None
    policy_code: str | None = None
    policy_type: str | None = None
    edition_label: str | None = None
    edition_code: str | None = None
    year: int | None = None
    guarantee: str | None = None
    overview_text: str | None = None
    definitions: list[str] = Field(default_factory=list)
    common_exclusions: list[str] = Field(default_factory=list)
    common_interpretations: list[str] = Field(default_factory=list)
    common_notes: list[str] = Field(default_factory=list)
    sections: list[BignamiSectionSummary] = Field(default_factory=list)
    coverage_items: list[BignamiCoverageItemSummary] = Field(default_factory=list)
    common_limits: list[BignamiCommonLimitSummary] = Field(default_factory=list)
    web_path: str | None = None
    match_score: float | None = None


def _clean(value: str | None) -> str | None:
    if value is None:
        return None
    stripped = value.strip()
    return stripped or None


def _like(value: str | None) -> str:
    return f"%{(value or '').strip()}%"


def _text_array(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return [str(item) for item in value if item is not None and str(item).strip()]
    return [str(value)] if str(value).strip() else []


def _optional_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


async def _summary_from_inputs(
    db: AsyncSession,
    *,
    company: str | None,
    policy_type: str | None,
    policy_number: str | None,
    guarantee: str | None,
) -> BignamiSummaryResponse:
    company = _clean(company)
    policy_type = _clean(policy_type)
    policy_number = _clean(policy_number)
    guarantee = _clean(guarantee)
    query_context = {
        "company": company,
        "policy_type": policy_type,
        "policy_number": policy_number,
        "guarantee": guarantee,
    }
    if not any(query_context.values()):
        return BignamiSummaryResponse(matched=False, query=query_context)

    params = {
        "company_blank": company is None,
        "policy_blank": policy_type is None,
        "policy_number_blank": policy_number is None,
        "guarantee_blank": guarantee is None,
        "company_like": _like(company),
        "policy_like": _like(policy_type),
        "policy_number_like": _like(policy_number),
        "guarantee_like": _like(guarantee),
    }

    try:
        candidate_result = await db.execute(
            text(
                """
                SELECT
                    c.name AS company_name,
                    c.code AS company_code,
                    p.id AS policy_id,
                    p.name AS policy_name,
                    p.code AS policy_code,
                    p.type AS policy_type,
                    p.description AS policy_description,
                    p.default_guarantee,
                    pe.id AS edition_id,
                    pe.year,
                    pe.edition_label,
                    pe.code AS edition_code,
                    pe.status AS edition_status,
                    cov.id AS coverage_id,
                    cov.guarantee,
                    cov.overview_text,
                    cov.definitions,
                    cov.common_exclusions,
                    cov.common_interpretations,
                    cov.common_notes,
                    (
                        CASE WHEN NOT :company_blank AND c.name ILIKE :company_like THEN 40 ELSE 0 END +
                        CASE WHEN NOT :company_blank AND EXISTS (
                            SELECT 1 FROM unnest(coalesce(c.aliases, ARRAY[]::text[])) alias
                            WHERE alias ILIKE :company_like
                        ) THEN 25 ELSE 0 END +
                        CASE WHEN NOT :policy_blank AND p.name ILIKE :policy_like THEN 22 ELSE 0 END +
                        CASE WHEN NOT :policy_blank AND p.description ILIKE :policy_like THEN 10 ELSE 0 END +
                        CASE WHEN NOT :policy_blank AND p.type ILIKE :policy_like THEN 12 ELSE 0 END +
                        CASE WHEN NOT :policy_blank AND EXISTS (
                            SELECT 1 FROM unnest(coalesce(p.tags, ARRAY[]::text[])) tag
                            WHERE tag ILIKE :policy_like
                        ) THEN 8 ELSE 0 END +
                        CASE WHEN NOT :policy_number_blank AND p.name ILIKE :policy_number_like THEN 6 ELSE 0 END +
                        CASE WHEN NOT :guarantee_blank AND cov.guarantee ILIKE :guarantee_like THEN 26 ELSE 0 END +
                        CASE WHEN NOT :guarantee_blank AND p.default_guarantee ILIKE :guarantee_like THEN 12 ELSE 0 END +
                        CASE WHEN pe.status = 'published' THEN 4 ELSE 0 END +
                        coalesce(pe.year, 0)::numeric / 10000
                    ) AS match_score
                FROM bignami.policies p
                JOIN bignami.companies c ON c.id = p.company_id
                JOIN bignami.policy_editions pe ON pe.policy_id = p.id
                LEFT JOIN bignami.coverages cov ON cov.policy_edition_id = pe.id
                WHERE cov.id IS NOT NULL
                  AND (
                    (NOT :company_blank AND c.name ILIKE :company_like)
                    OR (NOT :company_blank AND EXISTS (
                        SELECT 1 FROM unnest(coalesce(c.aliases, ARRAY[]::text[])) alias
                        WHERE alias ILIKE :company_like
                    ))
                    OR (NOT :policy_blank AND p.name ILIKE :policy_like)
                    OR (NOT :policy_blank AND p.description ILIKE :policy_like)
                    OR (NOT :policy_blank AND p.type ILIKE :policy_like)
                    OR (NOT :policy_blank AND EXISTS (
                        SELECT 1 FROM unnest(coalesce(p.tags, ARRAY[]::text[])) tag
                        WHERE tag ILIKE :policy_like
                    ))
                    OR (NOT :policy_number_blank AND p.name ILIKE :policy_number_like)
                    OR (NOT :guarantee_blank AND cov.guarantee ILIKE :guarantee_like)
                    OR (NOT :guarantee_blank AND p.default_guarantee ILIKE :guarantee_like)
                  )
                ORDER BY match_score DESC, pe.status = 'published' DESC, pe.year DESC NULLS LAST, p.created_at DESC
                LIMIT 1
                """
            ),
            params,
        )
        candidate = candidate_result.mappings().first()
    except SQLAlchemyError as exc:
        detail = str(exc).lower()
        if "bignami" in detail or "undefinedtable" in detail or "undefined schema" in detail:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Schema Bignami non disponibile: esegui la migrazione backend 018.",
            ) from exc
        raise

    if candidate is None:
        return BignamiSummaryResponse(matched=False, query=query_context)

    coverage_id = str(candidate["coverage_id"])
    sections_result = await db.execute(
        text(
            """
            SELECT party, exact_name, definition, value_type, primo_rischio_value,
                   deroga_percentage, determinazione, exclusions, notes,
                   page_reference, article_number, definition_page_reference,
                   definition_article_number
            FROM bignami.sections
            WHERE coverage_id = :coverage_id
            ORDER BY created_at ASC
            LIMIT 8
            """
        ),
        {"coverage_id": coverage_id},
    )
    items_result = await db.execute(
        text(
            """
            SELECT guarantee_name, guarantee_group, description, value_type,
                   maximum_value, deductible_value, guarantee_exclusions,
                   common_exclusions, maximum_page_reference, maximum_article_number
            FROM bignami.coverage_items
            WHERE coverage_id = :coverage_id
            ORDER BY order_index ASC, created_at ASC
            LIMIT 12
            """
        ),
        {"coverage_id": coverage_id},
    )
    limits_result = await db.execute(
        text(
            """
            SELECT label, scope, value, on_frontespizio, page_reference, article_number
            FROM bignami.common_limits
            WHERE coverage_id = :coverage_id
            ORDER BY created_at ASC
            LIMIT 8
            """
        ),
        {"coverage_id": coverage_id},
    )

    sections = [
        BignamiSectionSummary(
            party=row["party"],
            title=row["exact_name"] or row["party"],
            definition=row["definition"],
            value_type=row["value_type"],
            primo_rischio_value=row["primo_rischio_value"],
            deroga_percentage=_optional_float(row["deroga_percentage"]),
            determinazione=_text_array(row["determinazione"]),
            exclusions=_text_array(row["exclusions"]),
            notes=_text_array(row["notes"]),
            page_reference=row["definition_page_reference"] or row["page_reference"],
            article_number=row["definition_article_number"] or row["article_number"],
        )
        for row in sections_result.mappings().all()
    ]

    coverage_items = [
        BignamiCoverageItemSummary(
            guarantee_name=row["guarantee_name"],
            guarantee_group=row["guarantee_group"],
            description=row["description"],
            value_type=row["value_type"],
            maximum_value=row["maximum_value"],
            deductible_value=row["deductible_value"],
            guarantee_exclusions=_text_array(row["guarantee_exclusions"]),
            common_exclusions=_text_array(row["common_exclusions"]),
            page_reference=row["maximum_page_reference"],
            article_number=row["maximum_article_number"],
        )
        for row in items_result.mappings().all()
    ]

    common_limits = [
        BignamiCommonLimitSummary(
            label=row["label"],
            scope=row["scope"],
            value=row["value"],
            on_frontespizio=bool(row["on_frontespizio"]),
            page_reference=row["page_reference"],
            article_number=row["article_number"],
        )
        for row in limits_result.mappings().all()
    ]

    web_path = None
    if candidate["company_code"] and candidate["policy_code"]:
        web_path = f"/{candidate['company_code']}/{candidate['policy_code']}"
        if candidate["edition_code"]:
            web_path += f"/{candidate['edition_code']}"

    return BignamiSummaryResponse(
        matched=True,
        query=query_context,
        company_name=candidate["company_name"],
        company_code=candidate["company_code"],
        policy_name=candidate["policy_name"],
        policy_code=candidate["policy_code"],
        policy_type=candidate["policy_type"],
        edition_label=candidate["edition_label"],
        edition_code=candidate["edition_code"],
        year=candidate["year"],
        guarantee=candidate["guarantee"],
        overview_text=candidate["overview_text"],
        definitions=_text_array(candidate["definitions"]),
        common_exclusions=_text_array(candidate["common_exclusions"]),
        common_interpretations=_text_array(candidate["common_interpretations"]),
        common_notes=_text_array(candidate["common_notes"]),
        sections=sections,
        coverage_items=coverage_items,
        common_limits=common_limits,
        web_path=web_path,
        match_score=_optional_float(candidate["match_score"]),
    )


@router.get("/bignami/summary", response_model=BignamiSummaryResponse)
async def get_bignami_summary(
    company: str | None = Query(None),
    policy_type: str | None = Query(None),
    policy_number: str | None = Query(None),
    guarantee: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    _ = current_user
    return await _summary_from_inputs(
        db,
        company=company,
        policy_type=policy_type,
        policy_number=policy_number,
        guarantee=guarantee,
    )


@router.get("/bignami/claims/{claim_ref_or_id}/summary", response_model=BignamiSummaryResponse)
async def get_claim_bignami_summary(
    claim_ref_or_id: str,
    tenant_id: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    effective_tenant_id = tenant_id if current_user.is_platform_admin and tenant_id else current_user.tenant_id
    if tenant_id and tenant_id != current_user.tenant_id and not current_user.is_platform_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Tenant access denied")

    result = await db.execute(
        select(Claim).where(
            Claim.tenant_id == effective_tenant_id,
            or_(Claim.id == claim_ref_or_id, Claim.external_ref == claim_ref_or_id),
        )
    )
    claim = result.scalar_one_or_none()
    if claim is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Claim not found")

    return await _summary_from_inputs(
        db,
        company=claim.compagnia,
        policy_type=claim.tipo_polizza,
        policy_number=claim.numero_polizza,
        guarantee=claim.garanzia,
    )
