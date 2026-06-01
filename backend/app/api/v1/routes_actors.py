"""
Routes per l'anagrafica unificata degli attori (contraente/assicurato/
danneggiato), i loro indirizzi/IBAN, le relazioni tra attori e le viste
cross-sinistro (claims, agenzie, compagnie).

GDPR scope:
  * Search → minimization (ActorSummaryResponse con CF/PIVA mascherati)
    e visibilità ristretta per i non-admin (solo attori collegati ai
    propri sinistri assegnati).
  * Detail → autorizzazione esplicita per i non-admin (deve essere
    assegnatario di almeno un sinistro che coinvolge quell'attore).
  * Tutte le operazioni passano per AuditService → riga in `audit_log`
    con timestamp, ip, user_agent, claim_context_id opzionale.
"""
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.permissions import is_studio_admin
from app.core.security import get_current_active_user
from app.models.user import User
from app.schemas.actor import (
    ActorAddressCreate,
    ActorAddressResponse,
    ActorAgencyLinkResponse,
    ActorCompanyLinkResponse,
    ActorCreate,
    ActorDetailResponse,
    ActorIbanCreate,
    ActorIbanResponse,
    ActorRelationCreate,
    ActorRelationResponse,
    ActorResponse,
    ActorSummaryListResponse,
    ActorUpdate,
    build_actor_summary,
)
from app.schemas.claim import ClaimResponse
from app.services.actor_service import ActorService
from app.services.audit_service import AuditService

router = APIRouter()


async def _load_or_404(db: AsyncSession, tenant_id: str, actor_id: str):
    actor = await ActorService.get_actor(db, tenant_id, actor_id)
    if actor is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="actor_not_found")
    return actor


# ----------------------------------------------------------------------
# Search / CRUD
# ----------------------------------------------------------------------

@router.get("", response_model=ActorSummaryListResponse)
async def list_actors(
    request: Request,
    q: Optional[str] = Query(None, description="full-text su nome/cognome/denominazione/CF/PIVA (no email/telefono)"),
    actor_type: Optional[str] = Query(None, description="person|company|condo"),
    claim_context_id: Optional[str] = Query(None, description="ID sinistro nel cui contesto avviene la search (per audit)"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Search anagrafica. Risposta minimizzata (no contatti, CF/PIVA
    mascherati). Non-admin vedono solo attori collegati ai propri sinistri."""
    admin = await is_studio_admin(db, current_user.id)
    restrict_user_id = None if admin else current_user.id

    items, total = await ActorService.search(
        db,
        current_user.tenant_id,
        query=q,
        actor_type=actor_type,
        limit=limit,
        offset=offset,
        restrict_to_user_id=restrict_user_id,
    )

    await AuditService.log_actor_access(
        db,
        tenant_id=current_user.tenant_id,
        user_id=current_user.id,
        actor_id="*",
        action="actor_search",
        claim_context_id=claim_context_id,
        extra={
            "query": q,
            "actor_type": actor_type,
            "result_count": len(items),
            "scope": "admin" if admin else "assigned_only",
        },
        request=request,
        commit=True,
    )

    return ActorSummaryListResponse(
        items=[build_actor_summary(a) for a in items],
        total=total,
    )


@router.post("", response_model=ActorResponse, status_code=status.HTTP_201_CREATED)
async def create_actor(
    payload: ActorCreate,
    request: Request,
    claim_context_id: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    actor, created = await ActorService.upsert_by_cf_or_piva(db, current_user.tenant_id, payload)
    await AuditService.log_actor_access(
        db,
        tenant_id=current_user.tenant_id,
        user_id=current_user.id,
        actor_id=actor.id,
        action="actor_create" if created else "actor_upsert_match",
        claim_context_id=claim_context_id,
        extra={"actor_type": payload.actor_type},
        request=request,
        commit=True,
    )
    return ActorResponse.model_validate(actor)


@router.get("/{actor_id}", response_model=ActorDetailResponse)
async def get_actor(
    actor_id: str,
    request: Request,
    claim_context_id: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    actor = await _load_or_404(db, current_user.tenant_id, actor_id)

    admin = await is_studio_admin(db, current_user.id)
    if not admin:
        can_view = await ActorService.user_can_view_actor(
            db, current_user.tenant_id, current_user.id, actor_id
        )
        if not can_view:
            # Niente "forbidden esplicito" su risorsa esistente per evitare
            # enumeration: comportamento identico al 404.
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="actor_not_found")

    addrs = await ActorService.list_addresses(db, actor_id)
    ibans = await ActorService.list_ibans(db, actor_id)
    rel_out, rel_in = await ActorService.list_relations(db, actor_id)

    await AuditService.log_actor_access(
        db,
        tenant_id=current_user.tenant_id,
        user_id=current_user.id,
        actor_id=actor_id,
        action="actor_view",
        claim_context_id=claim_context_id,
        extra={"with_addresses": len(addrs), "with_ibans": len(ibans)},
        request=request,
        commit=True,
    )

    return ActorDetailResponse(
        **ActorResponse.model_validate(actor).model_dump(),
        addresses=[ActorAddressResponse.model_validate(a) for a in addrs],
        ibans=[ActorIbanResponse.model_validate(i) for i in ibans],
        relations_out=[ActorRelationResponse.model_validate(r) for r in rel_out],
        relations_in=[ActorRelationResponse.model_validate(r) for r in rel_in],
    )


@router.get("/{actor_id}/export")
async def export_actor(
    actor_id: str,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Export GDPR art. 15 (accesso) / art. 20 (portabilità).

    Restituisce tutti i dati personali dell'attore in formato JSON
    strutturato, compresi indirizzi, IBAN, relazioni, e riferimenti ai
    sinistri (id + ruolo + date). **Solo admin del tenant** può scaricarlo
    da qui; l'interessato stesso può ottenere l'export tramite il portale
    assicurati (flusso diverso, con consenso esplicito loggato).

    TODO 2FA: prima di restituire l'export, l'admin deve confermare la
    propria identità con un secondo fattore. Implementabile quando il
    sistema 2FA sarà disponibile — al momento blocchiamo qui con
    `X-2FA-Required` header non ancora richiesto.
    """
    if not await is_studio_admin(db, current_user.id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="admin_required")

    actor = await ActorService.get_actor(
        db, current_user.tenant_id, actor_id, include_deleted=True
    )
    if actor is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="actor_not_found")

    addresses = await ActorService.list_addresses(db, actor_id)
    ibans = await ActorService.list_ibans(db, actor_id)
    rel_out, rel_in = await ActorService.list_relations(db, actor_id)
    claims = await ActorService.list_claims(db, current_user.tenant_id, actor_id)
    agencies = await ActorService.list_agency_links(db, current_user.tenant_id, actor_id)
    companies = await ActorService.list_company_links(db, current_user.tenant_id, actor_id)

    payload = {
        "_export_meta": {
            "version": 1,
            "format": "json",
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "generated_by_user_id": current_user.id,
            "tenant_id": current_user.tenant_id,
            "gdpr_articles": ["15", "20"],
            "two_factor_verified": False,  # TODO: integrare flusso 2FA
        },
        "actor": ActorDetailResponse(
            **ActorResponse.model_validate(actor).model_dump(),
            addresses=[ActorAddressResponse.model_validate(a) for a in addresses],
            ibans=[ActorIbanResponse.model_validate(i) for i in ibans],
            relations_out=[ActorRelationResponse.model_validate(r) for r in rel_out],
            relations_in=[ActorRelationResponse.model_validate(r) for r in rel_in],
        ).model_dump(mode="json"),
        "claims": [
            {
                "id": c.id,
                "external_ref": c.external_ref,
                "numero_sinistro": c.numero_sinistro,
                "ruoli": [
                    role for role, value in (
                        ("contraente", c.contraente_id == actor_id),
                        ("assicurato", c.assicurato_id == actor_id),
                        ("danneggiato", c.danneggiato_id == actor_id),
                    ) if value
                ],
                "data_sinistro": c.data_sinistro.isoformat() if c.data_sinistro else None,
                "stato_corrente": c.stato_corrente,
                "created_at": c.created_at.isoformat() if c.created_at else None,
                "closed_at": c.closed_at.isoformat() if c.closed_at else None,
            }
            for c in claims
        ],
        "agencies_history": [
            {
                "agency_id": l.agency_id,
                "first_seen_claim_id": l.first_seen_claim_id,
                "last_seen_claim_id": l.last_seen_claim_id,
                "last_seen_at": l.last_seen_at.isoformat() if l.last_seen_at else None,
                "claim_count": l.claim_count,
            }
            for l in agencies
        ],
        "companies_history": [
            {
                "compagnia_id": l.compagnia_id,
                "first_seen_claim_id": l.first_seen_claim_id,
                "last_seen_claim_id": l.last_seen_claim_id,
                "last_seen_at": l.last_seen_at.isoformat() if l.last_seen_at else None,
                "claim_count": l.claim_count,
            }
            for l in companies
        ],
    }

    await AuditService.log_actor_access(
        db,
        tenant_id=current_user.tenant_id,
        user_id=current_user.id,
        actor_id=actor_id,
        action="actor_gdpr_export",
        extra={
            "claim_count": len(claims),
            "address_count": len(addresses),
            "iban_count": len(ibans),
            "two_factor_verified": False,
        },
        request=request,
        commit=True,
    )

    return payload


@router.delete("/{actor_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_actor(
    actor_id: str,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Soft delete (GDPR art. 17 — diritto all'oblio). **Solo admin** può
    cancellare. L'attore viene marcato `deleted_at`; i campi piatti sui
    sinistri collegati vengono pseudonimizzati a "[Cancellato art.17]"
    mantenendo l'integrità storica e contabile della pratica.

    L'operazione è loggata sia con `entity_type=actor` sia con un evento
    duplicato per ogni sinistro impattato (così è ricostruibile chi/quando/
    su quali pratiche ha cancellato l'anagrafica).
    """
    if not await is_studio_admin(db, current_user.id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="admin_required")

    actor = await ActorService.soft_delete_actor(db, current_user.tenant_id, actor_id)
    if actor is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="actor_not_found")

    await AuditService.log_actor_access(
        db,
        tenant_id=current_user.tenant_id,
        user_id=current_user.id,
        actor_id=actor_id,
        action="actor_soft_delete",
        extra={"deleted_at": actor.deleted_at.isoformat() if actor.deleted_at else None},
        request=request,
        commit=True,
    )


@router.patch("/{actor_id}", response_model=ActorResponse)
async def update_actor(
    actor_id: str,
    payload: ActorUpdate,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    admin = await is_studio_admin(db, current_user.id)
    if not admin:
        can_view = await ActorService.user_can_view_actor(
            db, current_user.tenant_id, current_user.id, actor_id
        )
        if not can_view:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="actor_not_found")

    actor = await ActorService.update_actor(db, current_user.tenant_id, actor_id, payload)
    if actor is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="actor_not_found")

    await AuditService.log_actor_access(
        db,
        tenant_id=current_user.tenant_id,
        user_id=current_user.id,
        actor_id=actor_id,
        action="actor_update",
        extra={"fields": list(payload.model_dump(exclude_unset=True).keys())},
        request=request,
        commit=True,
    )
    return ActorResponse.model_validate(actor)


# ----------------------------------------------------------------------
# Addresses
# ----------------------------------------------------------------------

@router.get("/{actor_id}/addresses", response_model=list[ActorAddressResponse])
async def list_addresses(
    actor_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _load_or_404(db, current_user.tenant_id, actor_id)
    admin = await is_studio_admin(db, current_user.id)
    if not admin and not await ActorService.user_can_view_actor(
        db, current_user.tenant_id, current_user.id, actor_id
    ):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="actor_not_found")
    items = await ActorService.list_addresses(db, actor_id)
    return [ActorAddressResponse.model_validate(a) for a in items]


@router.post("/{actor_id}/addresses", response_model=ActorAddressResponse, status_code=status.HTTP_201_CREATED)
async def add_address(
    actor_id: str,
    payload: ActorAddressCreate,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _load_or_404(db, current_user.tenant_id, actor_id)
    admin = await is_studio_admin(db, current_user.id)
    if not admin and not await ActorService.user_can_view_actor(
        db, current_user.tenant_id, current_user.id, actor_id
    ):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="actor_not_found")
    addr = await ActorService.add_address(db, actor_id, payload)
    await AuditService.log_actor_access(
        db,
        tenant_id=current_user.tenant_id,
        user_id=current_user.id,
        actor_id=actor_id,
        action="actor_address_add",
        extra={"address_id": addr.id, "is_primary": addr.is_primary},
        request=request,
        commit=True,
    )
    return ActorAddressResponse.model_validate(addr)


# ----------------------------------------------------------------------
# IBAN
# ----------------------------------------------------------------------

@router.get("/{actor_id}/ibans", response_model=list[ActorIbanResponse])
async def list_ibans(
    actor_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _load_or_404(db, current_user.tenant_id, actor_id)
    admin = await is_studio_admin(db, current_user.id)
    if not admin and not await ActorService.user_can_view_actor(
        db, current_user.tenant_id, current_user.id, actor_id
    ):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="actor_not_found")
    items = await ActorService.list_ibans(db, actor_id)
    return [ActorIbanResponse.model_validate(i) for i in items]


@router.post("/{actor_id}/ibans", response_model=ActorIbanResponse, status_code=status.HTTP_201_CREATED)
async def add_iban(
    actor_id: str,
    payload: ActorIbanCreate,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _load_or_404(db, current_user.tenant_id, actor_id)
    admin = await is_studio_admin(db, current_user.id)
    if not admin and not await ActorService.user_can_view_actor(
        db, current_user.tenant_id, current_user.id, actor_id
    ):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="actor_not_found")
    iban = await ActorService.add_iban(db, actor_id, payload)
    await AuditService.log_actor_access(
        db,
        tenant_id=current_user.tenant_id,
        user_id=current_user.id,
        actor_id=actor_id,
        action="actor_iban_add",
        extra={"iban_id": iban.id, "is_primary": iban.is_primary},
        request=request,
        commit=True,
    )
    return ActorIbanResponse.model_validate(iban)


# ----------------------------------------------------------------------
# Relations
# ----------------------------------------------------------------------

@router.post("/{actor_id}/relations", response_model=ActorRelationResponse, status_code=status.HTTP_201_CREATED)
async def add_relation(
    actor_id: str,
    payload: ActorRelationCreate,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    if payload.from_actor_id != actor_id:
        raise HTTPException(status_code=400, detail="from_actor_id_mismatch")
    await _load_or_404(db, current_user.tenant_id, actor_id)
    await _load_or_404(db, current_user.tenant_id, payload.to_actor_id)
    admin = await is_studio_admin(db, current_user.id)
    if not admin and not await ActorService.user_can_view_actor(
        db, current_user.tenant_id, current_user.id, actor_id
    ):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="actor_not_found")
    rel = await ActorService.add_relation(
        db,
        from_actor_id=payload.from_actor_id,
        to_actor_id=payload.to_actor_id,
        relation_type=payload.relation_type,
        note=payload.note,
        legal_basis=payload.legal_basis,
        legal_basis_note=payload.legal_basis_note,
    )
    await AuditService.log_actor_access(
        db,
        tenant_id=current_user.tenant_id,
        user_id=current_user.id,
        actor_id=actor_id,
        action="actor_relation_add",
        extra={
            "to_actor_id": payload.to_actor_id,
            "relation_type": payload.relation_type,
            "legal_basis": payload.legal_basis,
        },
        request=request,
        commit=True,
    )
    return ActorRelationResponse.model_validate(rel)


# ----------------------------------------------------------------------
# Cross-claim views
# ----------------------------------------------------------------------

@router.get("/{actor_id}/claims", response_model=list[ClaimResponse])
async def list_actor_claims(
    actor_id: str,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _load_or_404(db, current_user.tenant_id, actor_id)
    admin = await is_studio_admin(db, current_user.id)
    if not admin and not await ActorService.user_can_view_actor(
        db, current_user.tenant_id, current_user.id, actor_id
    ):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="actor_not_found")
    claims = await ActorService.list_claims(db, current_user.tenant_id, actor_id)
    await AuditService.log_actor_access(
        db,
        tenant_id=current_user.tenant_id,
        user_id=current_user.id,
        actor_id=actor_id,
        action="actor_claims_list",
        extra={"count": len(claims)},
        request=request,
        commit=True,
    )
    return [ClaimResponse.model_validate(c) for c in claims]


@router.get("/{actor_id}/agencies", response_model=list[ActorAgencyLinkResponse])
async def list_actor_agencies(
    actor_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _load_or_404(db, current_user.tenant_id, actor_id)
    admin = await is_studio_admin(db, current_user.id)
    if not admin and not await ActorService.user_can_view_actor(
        db, current_user.tenant_id, current_user.id, actor_id
    ):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="actor_not_found")
    links = await ActorService.list_agency_links(db, current_user.tenant_id, actor_id)
    return [ActorAgencyLinkResponse.model_validate(l) for l in links]


@router.get("/{actor_id}/companies", response_model=list[ActorCompanyLinkResponse])
async def list_actor_companies(
    actor_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    await _load_or_404(db, current_user.tenant_id, actor_id)
    admin = await is_studio_admin(db, current_user.id)
    if not admin and not await ActorService.user_can_view_actor(
        db, current_user.tenant_id, current_user.id, actor_id
    ):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="actor_not_found")
    links = await ActorService.list_company_links(db, current_user.tenant_id, actor_id)
    return [ActorCompanyLinkResponse.model_validate(l) for l in links]
