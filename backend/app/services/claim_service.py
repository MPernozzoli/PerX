"""
Claim service - business logic for claims
"""
from typing import Optional, List, Tuple
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import delete, select, func, update
from datetime import datetime

from app.models.claim import Claim
from app.models.claim_assignment import ClaimAssignment
from app.models.claim_event import ClaimEvent
from app.core.database import Base
import app.models  # noqa: F401 - ensure all model tables are registered in Base.metadata
from app.schemas.actor import ActorAddressSnapshot, ActorIbanSnapshot
from app.schemas.claim import ClaimActorInput, ClaimCreate, ClaimUpdate
from app.services.actor_service import ActorService


class ClaimService:
    @staticmethod
    async def _resolve_actor_input(
        db: AsyncSession,
        tenant_id: str,
        payload: Optional[ClaimActorInput],
    ) -> Tuple[Optional[str], Optional[ActorAddressSnapshot], Optional[ActorIbanSnapshot]]:
        """
        Risolve un ClaimActorInput in (actor_id, address_snapshot, iban_snapshot).

        - Se viene passato actor_id, lo usa direttamente.
        - Se viene passato actor_data, fa upsert per CF/PIVA.
        - Lo snapshot indirizzo/IBAN viene preso dall'address_id/iban_id
          specifico se fornito, altrimenti dal primary dell'attore.
        """
        if payload is None:
            return None, None, None

        actor_id: Optional[str] = payload.actor_id
        if actor_id is None and payload.actor_data is not None:
            actor, _ = await ActorService.upsert_by_cf_or_piva(
                db, tenant_id, payload.actor_data
            )
            actor_id = actor.id

        if actor_id is None:
            return None, None, None

        # Tenant check: l'address_id/iban_id arriva dal client, quindi
        # snapshot con tenant_id valida che appartenga a un attore di questo
        # tenant (no cross-tenant leak).
        if payload.address_id:
            addr_snap = await ActorService.snapshot_address(
                db, payload.address_id, tenant_id=tenant_id
            )
        else:
            addr = await ActorService.get_primary_address(db, actor_id)
            addr_snap = await ActorService.snapshot_address(db, addr.id) if addr else None

        if payload.iban_id:
            iban_snap = await ActorService.snapshot_iban(
                db, payload.iban_id, tenant_id=tenant_id
            )
        else:
            iban = await ActorService.get_primary_iban(db, actor_id)
            iban_snap = await ActorService.snapshot_iban(db, iban.id) if iban else None

        return actor_id, addr_snap, iban_snap

    @staticmethod
    async def create_claim(
        db: AsyncSession,
        tenant_id: str,
        claim_data: ClaimCreate,
        user_id: str
    ) -> Claim:
        """Create a new claim"""
        import uuid

        contraente_id, contraente_addr, contraente_iban = await ClaimService._resolve_actor_input(
            db, tenant_id, claim_data.contraente
        )
        assicurato_id, assicurato_addr, assicurato_iban = await ClaimService._resolve_actor_input(
            db, tenant_id, claim_data.assicurato
        )
        danneggiato_id, danneggiato_addr, danneggiato_iban = await ClaimService._resolve_actor_input(
            db, tenant_id, claim_data.danneggiato
        )

        # IBAN del sinistro = preferenza: danneggiato > contraente > assicurato.
        # (il danneggiato è chi riceve la liquidazione nella maggior parte dei casi)
        iban_snapshot = danneggiato_iban or contraente_iban or assicurato_iban

        # Se il client ha passato actor_id ma non i campi piatti, popoliamo i
        # campi piatti deprecated dall'Actor per compatibilità coi client legacy.
        flat_nome_ass = claim_data.nome_assicurato
        flat_email_ass = claim_data.email_assicurato
        flat_tel_ass = claim_data.telefono_assicurato
        flat_addr_ass = claim_data.indirizzo_assicurato
        flat_nome_contr = claim_data.nome_contraente
        flat_nome_dann = claim_data.nome_danneggiato
        if assicurato_id and not flat_nome_ass:
            actor = await ActorService.get_actor(db, tenant_id, assicurato_id)
            if actor:
                flat_nome_ass = actor.denominazione or " ".join(filter(None, [actor.nome, actor.cognome])) or None
                flat_email_ass = flat_email_ass or actor.email
                flat_tel_ass = flat_tel_ass or actor.telefono
                if assicurato_addr and not flat_addr_ass:
                    flat_addr_ass = ", ".join(filter(None, [
                        assicurato_addr.indirizzo,
                        assicurato_addr.civico,
                        assicurato_addr.cap,
                        assicurato_addr.citta,
                    ]))
        if contraente_id and not flat_nome_contr:
            actor = await ActorService.get_actor(db, tenant_id, contraente_id)
            if actor:
                flat_nome_contr = actor.denominazione or " ".join(filter(None, [actor.nome, actor.cognome])) or None
        if danneggiato_id and not flat_nome_dann:
            actor = await ActorService.get_actor(db, tenant_id, danneggiato_id)
            if actor:
                flat_nome_dann = actor.denominazione or " ".join(filter(None, [actor.nome, actor.cognome])) or None

        claim = Claim(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            external_ref=claim_data.external_ref,
            numero_sinistro=claim_data.numero_sinistro,
            compagnia=claim_data.compagnia,
            stato_corrente=claim_data.stato_corrente,
            garanzia=claim_data.garanzia or "Fenomeno Elettrico",
            agenzia=claim_data.agenzia,
            nome_assicurato=flat_nome_ass,
            email_assicurato=flat_email_ass,
            telefono_assicurato=flat_tel_ass,
            indirizzo_assicurato=flat_addr_ass,
            nome_contraente=flat_nome_contr,
            nome_danneggiato=flat_nome_dann,
            data_sinistro=claim_data.data_sinistro,
            richiesta=claim_data.richiesta,
            liquidato=claim_data.liquidato,
            numero_polizza=claim_data.numero_polizza,
            tipo_polizza=claim_data.tipo_polizza,
            contraente_id=contraente_id,
            assicurato_id=assicurato_id,
            danneggiato_id=danneggiato_id,
            agency_id=claim_data.agency_id,
            compagnia_id=claim_data.compagnia_id,
            contraente_address_snapshot=contraente_addr.model_dump() if contraente_addr else None,
            assicurato_address_snapshot=assicurato_addr.model_dump() if assicurato_addr else None,
            danneggiato_address_snapshot=danneggiato_addr.model_dump() if danneggiato_addr else None,
            iban_snapshot=iban_snapshot.model_dump() if iban_snapshot else None,
            version=1,
        )

        db.add(claim)
        await db.flush()

        # Aggiorna indici derivati actor <-> agency/compagnia per ognuno
        # dei ruoli presenti.
        actor_ids = {a for a in (contraente_id, assicurato_id, danneggiato_id) if a}
        for aid in actor_ids:
            if claim_data.agency_id:
                await ActorService.touch_agency_link(
                    db, tenant_id, aid, claim_data.agency_id, claim.id
                )
            if claim_data.compagnia_id:
                await ActorService.touch_company_link(
                    db, tenant_id, aid, claim_data.compagnia_id, claim.id
                )

        await db.commit()
        await db.refresh(claim)

        # Create event
        await ClaimService._create_event(
            db, tenant_id, claim.id, "claim_created", user_id, {"stato": claim_data.stato_corrente}
        )

        # Auto-provisioning portale assicurati (assicurato / contraente / danneggiato)
        # + invio email di benvenuto con magic link.
        try:
            from app.services.portal_service import PortalService
            await PortalService.provision_portal_access_for_claim(db, claim)
        except Exception:
            # Non bloccare la creazione del sinistro se il provisioning portale fallisce.
            await db.rollback()

        return claim
    
    @staticmethod
    async def get_claim(
        db: AsyncSession,
        tenant_id: Optional[str],
        claim_identifier: str
    ) -> Optional[Claim]:
        """Get a claim by ID or external reference"""
        query = select(Claim).where(
            (Claim.id == claim_identifier) | (Claim.external_ref == claim_identifier)
        )
        if tenant_id:
            query = query.where(Claim.tenant_id == tenant_id)
        result = await db.execute(query)
        return result.scalar_one_or_none()
    
    @staticmethod
    async def list_claims(
        db: AsyncSession,
        tenant_id: Optional[str],
        skip: int = 0,
        limit: int = 50,
        stato: Optional[str] = None,
        assignee_id: Optional[str] = None,
        search: Optional[str] = None
    ) -> tuple[List[Claim], int]:
        """List claims with filters and pagination"""
        query = select(Claim)
        if tenant_id:
            query = query.where(Claim.tenant_id == tenant_id)
        
        if stato:
            query = query.where(Claim.stato_corrente == stato)
        
        if assignee_id:
            query = query.join(
                ClaimAssignment,
                ClaimAssignment.claim_id == Claim.id
            ).where(
                ClaimAssignment.assignee_user_id == assignee_id,
                ClaimAssignment.unassigned_at.is_(None)
            )

        if search:
            query = query.where(
                (Claim.external_ref.ilike(f"%{search}%")) |
                (Claim.numero_sinistro.ilike(f"%{search}%")) |
                (Claim.compagnia.ilike(f"%{search}%")) |
                (Claim.nome_assicurato.ilike(f"%{search}%"))
            )
        
        # Count total
        count_query = select(func.count()).select_from(query.subquery())
        total_result = await db.execute(count_query)
        total = total_result.scalar() or 0
        
        # Apply pagination
        query = query.order_by(Claim.created_at.desc()).offset(skip).limit(limit)
        
        result = await db.execute(query)
        claims = result.scalars().all()
        
        return list(claims), total
    
    @staticmethod
    async def update_claim(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        claim_data: ClaimUpdate,
        user_id: str
    ) -> Optional[Claim]:
        """Update a claim with optimistic locking"""
        claim = await ClaimService.get_claim(db, tenant_id, claim_id)
        if not claim:
            return None
        
        # Check version for optimistic locking
        if claim.version != claim_data.version:
            from fastapi import HTTPException, status
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Version mismatch. Expected {claim.version}, got {claim_data.version}"
            )
        
        # Update fields
        if claim_data.external_ref is not None:
            claim.external_ref = claim_data.external_ref
        if claim_data.numero_sinistro is not None:
            claim.numero_sinistro = claim_data.numero_sinistro
        if claim_data.compagnia is not None:
            claim.compagnia = claim_data.compagnia
        if claim_data.garanzia is not None:
            claim.garanzia = claim_data.garanzia or "Fenomeno Elettrico"
        if claim_data.nome_assicurato is not None:
            claim.nome_assicurato = claim_data.nome_assicurato
        # ... update other fields as needed

        # Actor refs: se passati input strutturati, ririsolvi e aggiorna ruoli
        # + snapshot. Se passato solo l'id (in ClaimBase), applica diretto.
        agency_changed = False
        compagnia_changed = False
        if claim_data.agency_id is not None and claim.agency_id != claim_data.agency_id:
            claim.agency_id = claim_data.agency_id
            agency_changed = True
        if claim_data.compagnia_id is not None and claim.compagnia_id != claim_data.compagnia_id:
            claim.compagnia_id = claim_data.compagnia_id
            compagnia_changed = True

        for role, payload in (
            ("contraente", claim_data.contraente),
            ("assicurato", claim_data.assicurato),
            ("danneggiato", claim_data.danneggiato),
        ):
            if payload is None:
                continue
            aid, addr_snap, iban_snap = await ClaimService._resolve_actor_input(
                db, tenant_id, payload
            )
            setattr(claim, f"{role}_id", aid)
            setattr(
                claim,
                f"{role}_address_snapshot",
                addr_snap.model_dump() if addr_snap else None,
            )
            if role == "danneggiato" and iban_snap is not None:
                claim.iban_snapshot = iban_snap.model_dump()

        # Re-touch link indici se agency/compagnia o uno qualsiasi degli
        # actor refs sono cambiati.
        if agency_changed or compagnia_changed:
            actor_ids = {a for a in (claim.contraente_id, claim.assicurato_id, claim.danneggiato_id) if a}
            for aid in actor_ids:
                if claim.agency_id:
                    await ActorService.touch_agency_link(
                        db, tenant_id, aid, claim.agency_id, claim.id
                    )
                if claim.compagnia_id:
                    await ActorService.touch_company_link(
                        db, tenant_id, aid, claim.compagnia_id, claim.id
                    )

        claim.version += 1
        claim.updated_at = datetime.utcnow()

        await db.commit()
        await db.refresh(claim)
        
        # Create event
        await ClaimService._create_event(
            db, tenant_id, claim_id, "claim_updated", user_id, {}
        )
        
        return claim

    @staticmethod
    async def delete_claim(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        user_id: str
    ) -> bool:
        """Delete a claim and tenant-scoped claim-owned rows."""
        claim = await ClaimService.get_claim(db, tenant_id, claim_id)
        if not claim:
            return False

        resolved_claim_id = claim.id
        for table in reversed(Base.metadata.sorted_tables):
            if table.name == Claim.__tablename__ or "claim_id" not in table.c:
                continue

            claim_col = table.c.claim_id
            tenant_col = table.c.get("tenant_id")
            condition = claim_col == resolved_claim_id
            if tenant_col is not None:
                condition = condition & (tenant_col == tenant_id)

            if claim_col.nullable:
                await db.execute(update(table).where(condition).values(claim_id=None))
            else:
                await db.execute(delete(table).where(condition))

        await db.delete(claim)
        await db.commit()
        return True
    
    @staticmethod
    async def _create_event(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str,
        event_type: str,
        user_id: Optional[str],
        data: dict
    ):
        """Create a claim event"""
        import uuid
        event = ClaimEvent(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            claim_id=claim_id,
            event_type=event_type,
            actor_user_id=user_id,
            data_json=data,
            source="manual"
        )
        db.add(event)
        await db.commit()
