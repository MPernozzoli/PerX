"""
Claim service - business logic for claims
"""
from typing import Optional, List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_
from datetime import datetime

from app.models.claim import Claim
from app.models.claim_event import ClaimEvent
from app.schemas.claim import ClaimCreate, ClaimUpdate


class ClaimService:
    @staticmethod
    async def create_claim(
        db: AsyncSession,
        tenant_id: str,
        claim_data: ClaimCreate,
        user_id: str
    ) -> Claim:
        """Create a new claim"""
        import uuid
        
        claim = Claim(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            external_ref=claim_data.external_ref,
            numero_sinistro=claim_data.numero_sinistro,
            compagnia=claim_data.compagnia,
            stato_corrente=claim_data.stato_corrente,
            nome_assicurato=claim_data.nome_assicurato,
            email_assicurato=claim_data.email_assicurato,
            telefono_assicurato=claim_data.telefono_assicurato,
            indirizzo_assicurato=claim_data.indirizzo_assicurato,
            nome_contraente=claim_data.nome_contraente,
            nome_danneggiato=claim_data.nome_danneggiato,
            data_sinistro=claim_data.data_sinistro,
            richiesta=claim_data.richiesta,
            liquidato=claim_data.liquidato,
            numero_polizza=claim_data.numero_polizza,
            tipo_polizza=claim_data.tipo_polizza,
            version=1
        )
        
        db.add(claim)
        await db.commit()
        await db.refresh(claim)
        
        # Create event
        await ClaimService._create_event(
            db, tenant_id, claim.id, "claim_created", user_id, {"stato": claim_data.stato_corrente}
        )
        
        return claim
    
    @staticmethod
    async def get_claim(
        db: AsyncSession,
        tenant_id: str,
        claim_id: str
    ) -> Optional[Claim]:
        """Get a claim by ID"""
        result = await db.execute(
            select(Claim).where(
                and_(Claim.id == claim_id, Claim.tenant_id == tenant_id)
            )
        )
        return result.scalar_one_or_none()
    
    @staticmethod
    async def list_claims(
        db: AsyncSession,
        tenant_id: str,
        skip: int = 0,
        limit: int = 50,
        stato: Optional[str] = None,
        assignee_id: Optional[str] = None,
        search: Optional[str] = None
    ) -> tuple[List[Claim], int]:
        """List claims with filters and pagination"""
        query = select(Claim).where(Claim.tenant_id == tenant_id)
        
        if stato:
            query = query.where(Claim.stato_corrente == stato)
        
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
        if claim_data.nome_assicurato is not None:
            claim.nome_assicurato = claim_data.nome_assicurato
        # ... update other fields as needed
        
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

