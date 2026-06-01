"""
Actor service: gestione anagrafica unificata di contraenti/assicurati/danneggiati.

Funzioni principali:
  * upsert_by_cf_or_piva  - crea o trova un attore usando CF/PIVA come chiave naturale
  * add_address / add_iban / add_relation - sotto-entità con storico
  * snapshot_current_address / snapshot_current_iban - per fotografare i dati sul sinistro
  * touch_agency_link / touch_company_link - aggiornano gli indici derivati
  * list_claims / list_policies / list_agencies / list_companies - viste cross-sinistro
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import List, Optional, Tuple

from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.actor import (
    Actor,
    ActorAddress,
    ActorAgencyLink,
    ActorCompanyLink,
    ActorIban,
    ActorRelation,
)
from app.models.claim import Claim
from app.schemas.actor import (
    ActorAddressCreate,
    ActorAddressSnapshot,
    ActorCreate,
    ActorIbanCreate,
    ActorIbanSnapshot,
    ActorUpdate,
    RelationType,
)


def _norm(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    v = value.strip().upper()
    return v or None


class ActorService:
    # ------------------------------------------------------------------
    # CRUD
    # ------------------------------------------------------------------

    @staticmethod
    async def create_actor(
        db: AsyncSession,
        tenant_id: str,
        data: ActorCreate,
    ) -> Actor:
        actor = Actor(
            id=str(uuid.uuid4()),
            tenant_id=tenant_id,
            actor_type=data.actor_type,
            nome=data.nome,
            cognome=data.cognome,
            data_nascita=data.data_nascita,
            luogo_nascita=data.luogo_nascita,
            sesso=data.sesso,
            denominazione=data.denominazione,
            codice_fiscale=_norm(data.codice_fiscale),
            partita_iva=_norm(data.partita_iva),
            email=data.email,
            telefono=data.telefono,
            pec=data.pec,
            note=data.note,
        )
        db.add(actor)
        await db.flush()

        for addr in data.addresses or []:
            await ActorService.add_address(db, actor.id, addr, commit=False)
        for iban in data.ibans or []:
            await ActorService.add_iban(db, actor.id, iban, commit=False)

        await db.commit()
        await db.refresh(actor)
        return actor

    @staticmethod
    async def get_actor(
        db: AsyncSession,
        tenant_id: str,
        actor_id: str,
        *,
        include_deleted: bool = False,
    ) -> Optional[Actor]:
        conds = [Actor.id == actor_id, Actor.tenant_id == tenant_id]
        if not include_deleted:
            conds.append(Actor.deleted_at.is_(None))
        res = await db.execute(select(Actor).where(*conds))
        return res.scalar_one_or_none()

    @staticmethod
    async def update_actor(
        db: AsyncSession,
        tenant_id: str,
        actor_id: str,
        data: ActorUpdate,
    ) -> Optional[Actor]:
        actor = await ActorService.get_actor(db, tenant_id, actor_id)
        if actor is None:
            return None

        payload = data.model_dump(exclude_unset=True)
        if "codice_fiscale" in payload:
            payload["codice_fiscale"] = _norm(payload["codice_fiscale"])
        if "partita_iva" in payload:
            payload["partita_iva"] = _norm(payload["partita_iva"])

        for key, value in payload.items():
            setattr(actor, key, value)

        await db.commit()
        await db.refresh(actor)
        return actor

    # ------------------------------------------------------------------
    # Identity-based upsert
    # ------------------------------------------------------------------

    # ------------------------------------------------------------------
    # Soft delete (GDPR art. 17)
    # ------------------------------------------------------------------

    ANONYMIZED_PLACEHOLDER = "[Cancellato art.17]"

    @staticmethod
    async def soft_delete_actor(
        db: AsyncSession,
        tenant_id: str,
        actor_id: str,
    ) -> Optional[Actor]:
        """
        Marca l'attore come cancellato (`deleted_at = now()`) e anonimizza
        i campi piatti sui sinistri collegati (nome/email/telefono/indirizzo
        per il ruolo corrispondente). I `*_id` FK sui sinistri restano
        valorizzati: chiunque verifichi il record troverà un attore
        soft-deleted con dati pseudonimizzati, garantendo integrità storica
        senza esporre più i dati personali.

        I record di Address/Iban/Relations non vengono toccati qui: l'Actor
        è soft-deleted, e di conseguenza inaccessibile dagli endpoint
        standard (filtro `deleted_at IS NULL`).
        """
        actor = await ActorService.get_actor(db, tenant_id, actor_id, include_deleted=False)
        if actor is None:
            return None

        actor.deleted_at = datetime.now(timezone.utc)

        # Pseudonimizza i campi piatti su tutti i sinistri collegati,
        # ruolo per ruolo. Lasciamo `*_id` come riferimento storico.
        ph = ActorService.ANONYMIZED_PLACEHOLDER
        for role, name_col, email_col, tel_col, addr_col in (
            ("contraente", "nome_contraente", "email_contraente", "telefono_contraente", "indirizzo_contraente"),
            ("assicurato", "nome_assicurato", "email_assicurato", "telefono_assicurato", "indirizzo_assicurato"),
            ("danneggiato", "nome_danneggiato", "email_danneggiato", "telefono_danneggiato", "indirizzo_danneggiato"),
        ):
            id_col = getattr(Claim, f"{role}_id", None)
            if id_col is None:
                continue
            await db.execute(
                Claim.__table__.update()
                .where(id_col == actor_id, Claim.tenant_id == tenant_id)
                .values({
                    name_col: ph,
                    email_col: None,
                    tel_col: None,
                    addr_col: None,
                    f"{role}_address_snapshot": None,
                })
            )

        # Anche l'iban_snapshot del sinistro va azzerato se l'attore era
        # il "destinatario" della liquidazione (oggi tracciamo solo a livello
        # claim, non per attore: lo azzeriamo se l'attore è il danneggiato).
        await db.execute(
            Claim.__table__.update()
            .where(Claim.danneggiato_id == actor_id, Claim.tenant_id == tenant_id)
            .values(iban_snapshot=None)
        )

        await db.commit()
        await db.refresh(actor)
        return actor

    @staticmethod
    async def find_by_identity(
        db: AsyncSession,
        tenant_id: str,
        codice_fiscale: Optional[str] = None,
        partita_iva: Optional[str] = None,
    ) -> Optional[Actor]:
        cf = _norm(codice_fiscale)
        piva = _norm(partita_iva)
        if not cf and not piva:
            return None

        conditions = []
        if cf:
            conditions.append(Actor.codice_fiscale == cf)
        if piva:
            conditions.append(Actor.partita_iva == piva)

        res = await db.execute(
            select(Actor).where(
                Actor.tenant_id == tenant_id,
                Actor.deleted_at.is_(None),
                or_(*conditions),
            ).limit(1)
        )
        return res.scalar_one_or_none()

    @staticmethod
    async def upsert_by_cf_or_piva(
        db: AsyncSession,
        tenant_id: str,
        data: ActorCreate,
    ) -> Tuple[Actor, bool]:
        """
        Restituisce (actor, created). Se esiste già un attore con stesso
        CF/PIVA nel tenant, lo riusa senza sovrascrivere campi esistenti
        (i nuovi dati vengono usati solo per popolare i null).
        """
        existing = await ActorService.find_by_identity(
            db, tenant_id, data.codice_fiscale, data.partita_iva
        )
        if existing is not None:
            updated = False
            for field in (
                "nome", "cognome", "denominazione", "email", "telefono",
                "pec", "data_nascita", "luogo_nascita", "sesso", "note",
            ):
                if getattr(existing, field) in (None, "") and getattr(data, field):
                    setattr(existing, field, getattr(data, field))
                    updated = True
            if updated:
                await db.commit()
                await db.refresh(existing)
            return existing, False

        actor = await ActorService.create_actor(db, tenant_id, data)
        return actor, True

    # ------------------------------------------------------------------
    # Addresses
    # ------------------------------------------------------------------

    @staticmethod
    async def add_address(
        db: AsyncSession,
        actor_id: str,
        data: ActorAddressCreate,
        *,
        commit: bool = True,
    ) -> ActorAddress:
        if data.is_primary:
            # Solo un indirizzo "primary" per attore: smarca i precedenti.
            prev = await db.execute(
                select(ActorAddress).where(
                    ActorAddress.actor_id == actor_id,
                    ActorAddress.is_primary == True,  # noqa: E712
                )
            )
            for p in prev.scalars().all():
                p.is_primary = False

        addr = ActorAddress(
            id=str(uuid.uuid4()),
            actor_id=actor_id,
            **data.model_dump(),
        )
        db.add(addr)
        if commit:
            await db.commit()
            await db.refresh(addr)
        else:
            await db.flush()
        return addr

    @staticmethod
    async def list_addresses(db: AsyncSession, actor_id: str) -> List[ActorAddress]:
        res = await db.execute(
            select(ActorAddress)
            .where(ActorAddress.actor_id == actor_id)
            .order_by(ActorAddress.is_primary.desc(), ActorAddress.updated_at.desc())
        )
        return list(res.scalars().all())

    @staticmethod
    async def get_primary_address(db: AsyncSession, actor_id: str) -> Optional[ActorAddress]:
        """Primario se segnato, altrimenti il più recente, altrimenti None."""
        res = await db.execute(
            select(ActorAddress)
            .where(ActorAddress.actor_id == actor_id)
            .order_by(ActorAddress.is_primary.desc(), ActorAddress.updated_at.desc())
            .limit(1)
        )
        return res.scalar_one_or_none()

    @staticmethod
    async def snapshot_address(
        db: AsyncSession, address_id: str, *, tenant_id: Optional[str] = None
    ) -> Optional[ActorAddressSnapshot]:
        """Belt-and-braces tenant check: se `tenant_id` è passato, la query
        JOINa Actor per verificare che l'address appartenga a un attore del
        tenant indicato. Senza tenant_id la chiamata è considerata interna
        (chiamante responsabile della verifica)."""
        q = select(ActorAddress).where(ActorAddress.id == address_id)
        if tenant_id is not None:
            q = q.join(Actor, ActorAddress.actor_id == Actor.id).where(Actor.tenant_id == tenant_id)
        res = await db.execute(q)
        addr = res.scalar_one_or_none()
        if addr is None:
            return None
        return ActorAddressSnapshot(
            indirizzo=addr.indirizzo,
            civico=addr.civico,
            cap=addr.cap,
            citta=addr.citta,
            provincia=addr.provincia,
            nazione=addr.nazione,
        )

    # ------------------------------------------------------------------
    # IBAN
    # ------------------------------------------------------------------

    @staticmethod
    async def add_iban(
        db: AsyncSession,
        actor_id: str,
        data: ActorIbanCreate,
        *,
        commit: bool = True,
    ) -> ActorIban:
        if data.is_primary:
            prev = await db.execute(
                select(ActorIban).where(
                    ActorIban.actor_id == actor_id,
                    ActorIban.is_primary == True,  # noqa: E712
                )
            )
            for p in prev.scalars().all():
                p.is_primary = False

        iban = ActorIban(
            id=str(uuid.uuid4()),
            actor_id=actor_id,
            **data.model_dump(),
        )
        db.add(iban)
        if commit:
            await db.commit()
            await db.refresh(iban)
        else:
            await db.flush()
        return iban

    @staticmethod
    async def list_ibans(db: AsyncSession, actor_id: str) -> List[ActorIban]:
        res = await db.execute(
            select(ActorIban)
            .where(ActorIban.actor_id == actor_id)
            .order_by(ActorIban.is_primary.desc(), ActorIban.updated_at.desc())
        )
        return list(res.scalars().all())

    @staticmethod
    async def get_primary_iban(db: AsyncSession, actor_id: str) -> Optional[ActorIban]:
        res = await db.execute(
            select(ActorIban)
            .where(ActorIban.actor_id == actor_id)
            .order_by(ActorIban.is_primary.desc(), ActorIban.updated_at.desc())
            .limit(1)
        )
        return res.scalar_one_or_none()

    @staticmethod
    async def snapshot_iban(
        db: AsyncSession, iban_id: str, *, tenant_id: Optional[str] = None
    ) -> Optional[ActorIbanSnapshot]:
        """Vedi snapshot_address — stessa logica di tenant check opzionale."""
        q = select(ActorIban).where(ActorIban.id == iban_id)
        if tenant_id is not None:
            q = q.join(Actor, ActorIban.actor_id == Actor.id).where(Actor.tenant_id == tenant_id)
        res = await db.execute(q)
        iban = res.scalar_one_or_none()
        if iban is None:
            return None
        return ActorIbanSnapshot(
            iban=iban.iban,
            intestatario=iban.intestatario,
            banca=iban.banca,
        )

    # ------------------------------------------------------------------
    # Relations
    # ------------------------------------------------------------------

    @staticmethod
    async def add_relation(
        db: AsyncSession,
        from_actor_id: str,
        to_actor_id: str,
        relation_type: RelationType,
        note: Optional[str] = None,
        legal_basis: Optional[str] = None,
        legal_basis_note: Optional[str] = None,
    ) -> ActorRelation:
        rel = ActorRelation(
            id=str(uuid.uuid4()),
            from_actor_id=from_actor_id,
            to_actor_id=to_actor_id,
            relation_type=relation_type,
            note=note,
            legal_basis=legal_basis,
            legal_basis_note=legal_basis_note,
        )
        db.add(rel)
        await db.commit()
        await db.refresh(rel)
        return rel

    @staticmethod
    async def list_relations(
        db: AsyncSession, actor_id: str
    ) -> Tuple[List[ActorRelation], List[ActorRelation]]:
        out = (await db.execute(
            select(ActorRelation).where(ActorRelation.from_actor_id == actor_id)
        )).scalars().all()
        inc = (await db.execute(
            select(ActorRelation).where(ActorRelation.to_actor_id == actor_id)
        )).scalars().all()
        return list(out), list(inc)

    # ------------------------------------------------------------------
    # Derived indices (agency / company)
    # ------------------------------------------------------------------

    @staticmethod
    async def touch_agency_link(
        db: AsyncSession,
        tenant_id: str,
        actor_id: str,
        agency_id: str,
        claim_id: str,
    ) -> ActorAgencyLink:
        res = await db.execute(
            select(ActorAgencyLink).where(
                ActorAgencyLink.actor_id == actor_id,
                ActorAgencyLink.agency_id == agency_id,
            )
        )
        link = res.scalar_one_or_none()
        if link is None:
            link = ActorAgencyLink(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                actor_id=actor_id,
                agency_id=agency_id,
                first_seen_claim_id=claim_id,
                last_seen_claim_id=claim_id,
                last_seen_at=datetime.now(timezone.utc),
                claim_count=1,
            )
            db.add(link)
        else:
            link.last_seen_claim_id = claim_id
            link.last_seen_at = datetime.now(timezone.utc)
            link.claim_count = (link.claim_count or 0) + 1
        await db.flush()
        return link

    @staticmethod
    async def touch_company_link(
        db: AsyncSession,
        tenant_id: str,
        actor_id: str,
        compagnia_id: str,
        claim_id: str,
    ) -> ActorCompanyLink:
        res = await db.execute(
            select(ActorCompanyLink).where(
                ActorCompanyLink.actor_id == actor_id,
                ActorCompanyLink.compagnia_id == compagnia_id,
            )
        )
        link = res.scalar_one_or_none()
        if link is None:
            link = ActorCompanyLink(
                id=str(uuid.uuid4()),
                tenant_id=tenant_id,
                actor_id=actor_id,
                compagnia_id=compagnia_id,
                first_seen_claim_id=claim_id,
                last_seen_claim_id=claim_id,
                last_seen_at=datetime.now(timezone.utc),
                claim_count=1,
            )
            db.add(link)
        else:
            link.last_seen_claim_id = claim_id
            link.last_seen_at = datetime.now(timezone.utc)
            link.claim_count = (link.claim_count or 0) + 1
        await db.flush()
        return link

    # ------------------------------------------------------------------
    # Cross-claim views
    # ------------------------------------------------------------------

    @staticmethod
    async def list_claims(
        db: AsyncSession, tenant_id: str, actor_id: str
    ) -> List[Claim]:
        """
        Tutti i sinistri in cui l'attore compare in uno qualsiasi dei
        ruoli (contraente/assicurato/danneggiato). Assume che Claim abbia
        i campi contraente_id/assicurato_id/danneggiato_id; finché non
        sono aggiunti, ritorna [].
        """
        contraente_col = getattr(Claim, "contraente_id", None)
        assicurato_col = getattr(Claim, "assicurato_id", None)
        danneggiato_col = getattr(Claim, "danneggiato_id", None)
        cols = [c for c in (contraente_col, assicurato_col, danneggiato_col) if c is not None]
        if not cols:
            return []

        res = await db.execute(
            select(Claim).where(
                Claim.tenant_id == tenant_id,
                or_(*[col == actor_id for col in cols]),
            ).order_by(Claim.created_at.desc())
        )
        return list(res.scalars().all())

    @staticmethod
    async def list_agency_links(
        db: AsyncSession, tenant_id: str, actor_id: str
    ) -> List[ActorAgencyLink]:
        res = await db.execute(
            select(ActorAgencyLink).where(
                ActorAgencyLink.tenant_id == tenant_id,
                ActorAgencyLink.actor_id == actor_id,
            ).order_by(ActorAgencyLink.last_seen_at.desc())
        )
        return list(res.scalars().all())

    @staticmethod
    async def list_company_links(
        db: AsyncSession, tenant_id: str, actor_id: str
    ) -> List[ActorCompanyLink]:
        res = await db.execute(
            select(ActorCompanyLink).where(
                ActorCompanyLink.tenant_id == tenant_id,
                ActorCompanyLink.actor_id == actor_id,
            ).order_by(ActorCompanyLink.last_seen_at.desc())
        )
        return list(res.scalars().all())

    @staticmethod
    async def search(
        db: AsyncSession,
        tenant_id: str,
        query: Optional[str] = None,
        actor_type: Optional[str] = None,
        limit: int = 50,
        offset: int = 0,
        restrict_to_user_id: Optional[str] = None,
    ) -> Tuple[List[Actor], int]:
        """
        Search per anagrafica. GDPR-aware:

        - **Niente reverse-lookup**: la query NON matcha mai email o telefono
          (eviterebbe l'uso dell'app come "is this email registered" oracle).
          Si cerca solo su nome/cognome/denominazione/CF/PIVA.
        - **Scope per ruolo**: se `restrict_to_user_id` è valorizzato, la
          search restituisce solo attori collegati a sinistri assegnati a
          quell'utente (in uno qualsiasi dei 3 ruoli). Gli admin studio
          devono passare None per vedere l'anagrafica completa del tenant.
        - **Minima query**: ignoriamo query troppo corte (< 2 char) per
          ridurre fishing-style probing.
        """
        conditions = [Actor.tenant_id == tenant_id, Actor.deleted_at.is_(None)]
        if actor_type:
            conditions.append(Actor.actor_type == actor_type)

        q_trim = (query or "").strip()
        if q_trim and len(q_trim) >= 2:
            q = f"%{q_trim}%"
            q_upper = f"%{q_trim.upper()}%"
            conditions.append(
                or_(
                    Actor.nome.ilike(q),
                    Actor.cognome.ilike(q),
                    Actor.denominazione.ilike(q),
                    Actor.codice_fiscale.ilike(q_upper),
                    Actor.partita_iva.ilike(q_upper),
                )
            )
        elif q_trim:
            # Query troppo corta: ritorna vuoto, non l'intera anagrafica.
            return [], 0

        # Scope visibilità: solo attori collegati a sinistri assegnati
        # all'utente corrente (via ClaimAssignment attivo).
        if restrict_to_user_id is not None:
            from app.models.claim_assignment import ClaimAssignment
            allowed_actor_ids = (
                select(Claim.contraente_id).where(
                    Claim.tenant_id == tenant_id,
                    Claim.id.in_(
                        select(ClaimAssignment.claim_id).where(
                            ClaimAssignment.assignee_user_id == restrict_to_user_id,
                            ClaimAssignment.unassigned_at.is_(None),
                        )
                    ),
                    Claim.contraente_id.isnot(None),
                )
                .union(
                    select(Claim.assicurato_id).where(
                        Claim.tenant_id == tenant_id,
                        Claim.id.in_(
                            select(ClaimAssignment.claim_id).where(
                                ClaimAssignment.assignee_user_id == restrict_to_user_id,
                                ClaimAssignment.unassigned_at.is_(None),
                            )
                        ),
                        Claim.assicurato_id.isnot(None),
                    )
                )
                .union(
                    select(Claim.danneggiato_id).where(
                        Claim.tenant_id == tenant_id,
                        Claim.id.in_(
                            select(ClaimAssignment.claim_id).where(
                                ClaimAssignment.assignee_user_id == restrict_to_user_id,
                                ClaimAssignment.unassigned_at.is_(None),
                            )
                        ),
                        Claim.danneggiato_id.isnot(None),
                    )
                )
            )
            conditions.append(Actor.id.in_(allowed_actor_ids))

        total = (await db.execute(
            select(func.count()).select_from(Actor).where(and_(*conditions))
        )).scalar_one()

        res = await db.execute(
            select(Actor)
            .where(and_(*conditions))
            .order_by(Actor.updated_at.desc())
            .limit(limit)
            .offset(offset)
        )
        return list(res.scalars().all()), int(total or 0)

    # ------------------------------------------------------------------
    # Visibility check for single actor
    # ------------------------------------------------------------------

    @staticmethod
    async def user_can_view_actor(
        db: AsyncSession,
        tenant_id: str,
        user_id: str,
        actor_id: str,
    ) -> bool:
        """
        True se l'utente è assegnatario di almeno un sinistro in cui
        l'attore compare (in uno qualsiasi dei 3 ruoli). Usato per
        autorizzare GET /actors/{id} ai non-admin.
        """
        from app.models.claim_assignment import ClaimAssignment
        q = select(func.count()).select_from(Claim).where(
            Claim.tenant_id == tenant_id,
            or_(
                Claim.contraente_id == actor_id,
                Claim.assicurato_id == actor_id,
                Claim.danneggiato_id == actor_id,
            ),
            Claim.id.in_(
                select(ClaimAssignment.claim_id).where(
                    ClaimAssignment.assignee_user_id == user_id,
                    ClaimAssignment.unassigned_at.is_(None),
                )
            ),
        )
        n = (await db.execute(q)).scalar_one()
        return int(n or 0) > 0
