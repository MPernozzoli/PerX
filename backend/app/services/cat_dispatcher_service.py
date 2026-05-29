"""
CAT Dispatcher domain service.

This module intentionally keeps CatDispatcher behind API boundaries while using
the same Supabase Postgres database as the PerX backend.
"""
from __future__ import annotations

import json
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


def _items(result) -> list[dict[str, Any]]:
    return [dict(row) for row in result.mappings().all()]


def _item(result) -> dict[str, Any] | None:
    row = result.mappings().first()
    return dict(row) if row else None


def _json_param(value: Any) -> str:
    return json.dumps(value if isinstance(value, dict) else {}, ensure_ascii=False)


class CatDispatcherService:
    @staticmethod
    async def map_data(db: AsyncSession) -> dict[str, Any]:
        communes = _items(await db.execute(text("SELECT * FROM communes ORDER BY comune, quartiere NULLS FIRST")))
        cats = _items(await db.execute(text("SELECT * FROM cats ORDER BY name")))
        associations = _items(await db.execute(text("SELECT * FROM cat_commune WHERE active = true")))
        suspensions = _items(await db.execute(
            text("SELECT * FROM cat_suspensions WHERE start_date <= CURRENT_DATE AND end_date >= CURRENT_DATE")
        ))
        return {
            "communes": communes,
            "cats": cats,
            "associations": associations,
            "suspended_cat_ids": [item["cat_id"] for item in suspensions],
            "suspensions": suspensions,
            "metadata": {
                "total_communes": len(communes),
                "total_cats": len(cats),
                "total_associations": len(associations),
                "total_suspended": len(suspensions),
                "cache_version": 1,
            },
        }

    @staticmethod
    async def search(db: AsyncSession, query: str) -> dict[str, Any]:
        term = f"%{query.strip()}%"
        communes = _items(await db.execute(
            text(
                """
                SELECT c.*, cat.name AS cat_name, cat.color_hex AS cat_color
                FROM communes c
                LEFT JOIN cat_commune cc ON cc.commune_id = c.id AND cc.active = true AND cc.is_primary = true
                LEFT JOIN cats cat ON cat.id = cc.cat_id
                WHERE c.comune ILIKE :term OR c.alias ILIKE :term OR c.quartiere ILIKE :term
                ORDER BY c.comune, c.quartiere NULLS FIRST
                LIMIT 25
                """
            ),
            {"term": term},
        ))
        cats = _items(await db.execute(
            text("SELECT id, name, color_hex FROM cats WHERE name ILIKE :term ORDER BY name LIMIT 15"),
            {"term": term},
        ))
        return {"results": {"communes": communes, "cats": cats}}

    @staticmethod
    async def commune_details(db: AsyncSession, commune_id: str) -> dict[str, Any]:
        commune = _item(await db.execute(text("SELECT * FROM communes WHERE id = :id"), {"id": commune_id}))
        if not commune:
            return {"commune": None, "catAssociations": [], "suspensions": [], "parentCommune": None, "neighborhoods": []}
        associations_rows = _items(await db.execute(
            text(
                """
                SELECT cc.id, cc.is_primary, cc.intervention_type, cc.active,
                       c.id AS cat_id, c.name, c.color_hex, c.active AS cat_active
                FROM cat_commune cc
                JOIN cats c ON c.id = cc.cat_id
                WHERE cc.commune_id = :commune_id AND cc.active = true
                ORDER BY cc.is_primary DESC, c.name
                """
            ),
            {"commune_id": commune_id},
        ))
        cat_ids = [row["cat_id"] for row in associations_rows]
        suspensions = []
        if cat_ids:
            suspensions = _items(await db.execute(
                text(
                    """
                    SELECT * FROM cat_suspensions
                    WHERE cat_id = ANY(:cat_ids)
                      AND start_date <= CURRENT_DATE
                      AND end_date >= CURRENT_DATE
                    """
                ),
                {"cat_ids": cat_ids},
            ))
        parent = None
        neighborhoods: list[dict[str, Any]] = []
        if commune.get("quartiere"):
            parent = _item(await db.execute(
                text("SELECT * FROM communes WHERE comune = :comune AND quartiere IS NULL LIMIT 1"),
                {"comune": commune["comune"]},
            ))
        else:
            neighborhoods = _items(await db.execute(
                text("SELECT * FROM communes WHERE comune = :comune AND quartiere IS NOT NULL AND quartiere != '' ORDER BY quartiere"),
                {"comune": commune["comune"]},
            ))
        return {
            "commune": commune,
            "catAssociations": [
                {
                    "id": row["id"],
                    "is_primary": row["is_primary"],
                    "intervention_type": row["intervention_type"],
                    "active": row["active"],
                    "cats": {
                        "id": row["cat_id"],
                        "name": row["name"],
                        "color_hex": row["color_hex"],
                        "active": row["cat_active"],
                    },
                }
                for row in associations_rows
            ],
            "suspensions": suspensions,
            "parentCommune": parent,
            "neighborhoods": neighborhoods,
        }

    @staticmethod
    async def lookup_by_commune(
        db: AsyncSession,
        comune: str,
        provincia: str | None,
        intervention_type: str = "sopralluogo",
    ) -> dict[str, Any]:
        commune_result = await db.execute(
            text(
                """
                SELECT id, comune
                FROM communes
                WHERE lower(comune) = lower(:comune)
                  AND (:provincia IS NULL OR lower(left(coalesce(provincia, ''), 2)) = lower(left(:provincia, 2)))
                ORDER BY CASE WHEN quartiere IS NULL THEN 0 ELSE 1 END
                LIMIT 1
                """
            ),
            {"comune": comune.strip(), "provincia": provincia.strip() if provincia else None},
        )
        commune = _item(commune_result)
        if not commune:
            return {"success": False, "error": "Comune non trovato"}

        association_result = await db.execute(
            text(
                """
                SELECT
                  c.id,
                  c.name,
                  c.active,
                  cc.is_primary,
                  s.reason AS suspension_reason,
                  s.end_date AS suspension_end_date
                FROM cat_commune cc
                JOIN cats c ON c.id = cc.cat_id
                LEFT JOIN cat_suspensions s ON s.cat_id = c.id
                  AND s.start_date <= CURRENT_DATE
                  AND s.end_date >= CURRENT_DATE
                WHERE cc.commune_id = :commune_id
                  AND cc.active = true
                  AND (cc.intervention_type = :intervention_type OR cc.intervention_type = 'both')
                ORDER BY
                  CASE WHEN c.active = true AND s.id IS NULL THEN 0 ELSE 1 END,
                  cc.is_primary DESC NULLS LAST,
                  c.name ASC
                """
            ),
            {"commune_id": commune["id"], "intervention_type": intervention_type},
        )
        associations = _items(association_result)
        if not associations:
            return {"success": False, "error": "Nessun CAT assegnato"}

        available = [item for item in associations if item["active"] and item["suspension_reason"] is None]
        if available:
            selected = available[0]
            return {
                "success": True,
                "cat_id": selected["id"],
                "cat_name": selected["name"],
                "cat_alias": selected["name"],
                "commune_name": commune["comune"],
                "multiple_cats": len(available) > 1,
                "needs_geocoding": False,
            }

        selected = associations[0]
        return {
            "success": False,
            "suspended": True,
            "cat_id": selected["id"],
            "cat_name": selected["name"],
            "cat_alias": selected["name"],
            "commune_name": commune["comune"],
            "suspension_reason": selected["suspension_reason"] or "disattivato",
            "suspension_end_date": selected["suspension_end_date"],
        }

    @classmethod
    async def lookup_by_address(cls, db: AsyncSession, payload: dict[str, Any]) -> dict[str, Any]:
        comune = payload.get("comune")
        if not isinstance(comune, str) or not comune.strip():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Per il modulo integrato serve almeno il comune. La geocodifica indirizzo verra collegata al backend PerX.",
            )
        provincia = payload.get("provincia") if isinstance(payload.get("provincia"), str) else None
        intervention_type = payload.get("intervention_type") if isinstance(payload.get("intervention_type"), str) else "sopralluogo"
        return await cls.lookup_by_commune(db, comune, provincia, intervention_type)

    @staticmethod
    async def get_availability(db: AsyncSession, cat_id: str) -> dict[str, Any]:
        rules = await db.execute(
            text(
                """
                SELECT *
                FROM cat_availability_rules
                WHERE cat_id = :cat_id AND active = true
                ORDER BY weekday ASC, start_time ASC
                """
            ),
            {"cat_id": cat_id},
        )
        overrides = await db.execute(
            text(
                """
                SELECT *
                FROM cat_availability_overrides
                WHERE cat_id = :cat_id
                ORDER BY availability_date ASC
                """
            ),
            {"cat_id": cat_id},
        )
        return {"success": True, "rules": _items(rules), "overrides": _items(overrides)}

    @staticmethod
    async def replace_availability_rules(db: AsyncSession, cat_id: str, rules: list[dict[str, Any]]) -> dict[str, Any]:
        await db.execute(text("DELETE FROM cat_availability_rules WHERE cat_id = :cat_id"), {"cat_id": cat_id})
        created: list[dict[str, Any]] = []
        for rule in rules:
            result = await db.execute(
                text(
                    """
                    INSERT INTO cat_availability_rules
                      (cat_id, weekday, start_time, end_time, capacity, active, notes, metadata_json)
                    VALUES
                      (:cat_id, :weekday, :start_time, :end_time, :capacity, :active, :notes, cast(:metadata_json as jsonb))
                    RETURNING *
                    """
                ),
                {
                    "cat_id": cat_id,
                    "weekday": rule.get("weekday"),
                    "start_time": rule.get("start_time"),
                    "end_time": rule.get("end_time"),
                    "capacity": rule.get("capacity", 1),
                    "active": rule.get("active", True),
                    "notes": rule.get("notes"),
                    "metadata_json": _json_param(rule.get("metadata")),
                },
            )
            item = _item(result)
            if item:
                created.append(item)
        await db.commit()
        return {"success": True, "items": created}

    @staticmethod
    async def create_availability_override(db: AsyncSession, payload: dict[str, Any]) -> dict[str, Any]:
        result = await db.execute(
            text(
                """
                INSERT INTO cat_availability_overrides
                  (cat_id, availability_date, is_available, start_time, end_time, capacity, reason, metadata_json)
                VALUES
                  (:cat_id, :availability_date, :is_available, :start_time, :end_time, :capacity, :reason, cast(:metadata_json as jsonb))
                RETURNING *
                """
            ),
            {
                "cat_id": payload.get("cat_id"),
                "availability_date": payload.get("availability_date"),
                "is_available": payload.get("is_available", True),
                "start_time": payload.get("start_time"),
                "end_time": payload.get("end_time"),
                "capacity": payload.get("capacity", 1),
                "reason": payload.get("reason"),
                "metadata_json": _json_param(payload.get("metadata")),
            },
        )
        await db.commit()
        return {"success": True, "item": _item(result)}

    @staticmethod
    async def create_request(db: AsyncSession, tenant_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        result = await db.execute(
            text(
                """
                INSERT INTO dispatch_requests
                  (tenant_id, external_source, tenant_domain, external_claim_id, claim_reference,
                   intervention_type, priority, address_line, comune, provincia, commune_id,
                   latitude, longitude, requested_duration_minutes, due_at, notes, metadata_json)
                VALUES
                  (:tenant_id, :external_source, :tenant_domain, :external_claim_id, :claim_reference,
                   :intervention_type, :priority, :address_line, :comune, :provincia, :commune_id,
                   :latitude, :longitude, :requested_duration_minutes, :due_at, :notes, cast(:metadata_json as jsonb))
                RETURNING *
                """
            ),
            {
                "tenant_id": tenant_id,
                "external_source": payload.get("external_source", "perx_backend"),
                "tenant_domain": payload.get("tenant_domain"),
                "external_claim_id": payload.get("external_claim_id"),
                "claim_reference": payload.get("claim_reference"),
                "intervention_type": payload.get("intervention_type", "sopralluogo"),
                "priority": payload.get("priority", 0),
                "address_line": payload.get("address_line"),
                "comune": payload.get("comune"),
                "provincia": payload.get("provincia"),
                "commune_id": payload.get("commune_id"),
                "latitude": payload.get("latitude"),
                "longitude": payload.get("longitude"),
                "requested_duration_minutes": payload.get("requested_duration_minutes", 45),
                "due_at": payload.get("due_at"),
                "notes": payload.get("notes"),
                "metadata_json": _json_param(payload.get("metadata")),
            },
        )
        await db.commit()
        return {"success": True, "request": _item(result)}

    @staticmethod
    async def replace_insured_windows(db: AsyncSession, payload: dict[str, Any]) -> dict[str, Any]:
        dispatch_request_id = payload.get("dispatch_request_id")
        await db.execute(
            text("DELETE FROM insured_availability_windows WHERE dispatch_request_id = :dispatch_request_id"),
            {"dispatch_request_id": dispatch_request_id},
        )
        created: list[dict[str, Any]] = []
        for window in payload.get("windows") or []:
            result = await db.execute(
                text(
                    """
                    INSERT INTO insured_availability_windows
                      (dispatch_request_id, window_date, start_time, end_time, preference_rank, source, notes, metadata_json)
                    VALUES
                      (:dispatch_request_id, :window_date, :start_time, :end_time, :preference_rank, :source, :notes, cast(:metadata_json as jsonb))
                    RETURNING *
                    """
                ),
                {
                    "dispatch_request_id": dispatch_request_id,
                    "window_date": window.get("window_date"),
                    "start_time": window.get("start_time"),
                    "end_time": window.get("end_time"),
                    "preference_rank": window.get("preference_rank", 0),
                    "source": window.get("source", "insured_portal"),
                    "notes": window.get("notes"),
                    "metadata_json": _json_param(window.get("metadata")),
                },
            )
            item = _item(result)
            if item:
                created.append(item)
        await db.commit()
        return {"success": True, "items": created}

    @staticmethod
    async def create_assignment(db: AsyncSession, payload: dict[str, Any]) -> dict[str, Any]:
        result = await db.execute(
            text(
                """
                INSERT INTO cat_assignments
                  (dispatch_request_id, cat_id, status, scheduled_start, scheduled_end, score, decision_reason, metadata_json)
                VALUES
                  (:dispatch_request_id, :cat_id, :status, :scheduled_start, :scheduled_end, :score, :decision_reason, cast(:metadata_json as jsonb))
                RETURNING *
                """
            ),
            {
                "dispatch_request_id": payload.get("dispatch_request_id"),
                "cat_id": payload.get("cat_id"),
                "status": payload.get("status", "proposed"),
                "scheduled_start": payload.get("scheduled_start"),
                "scheduled_end": payload.get("scheduled_end"),
                "score": payload.get("score"),
                "decision_reason": payload.get("decision_reason"),
                "metadata_json": _json_param(payload.get("metadata")),
            },
        )
        assignment = _item(result)
        if assignment:
            await db.execute(
                text(
                    """
                    UPDATE dispatch_requests
                    SET assigned_cat_id = :cat_id,
                        status = :status,
                        updated_at = now()
                    WHERE id = :dispatch_request_id
                    """
                ),
                {
                    "cat_id": assignment["cat_id"],
                    "dispatch_request_id": assignment["dispatch_request_id"],
                    "status": "scheduled" if assignment.get("scheduled_start") and assignment.get("scheduled_end") else "assigned",
                },
            )
        await db.commit()
        return {"success": True, "assignment": assignment}

    @staticmethod
    async def create_route_plan(db: AsyncSession, payload: dict[str, Any]) -> dict[str, Any]:
        assignment_ids = [item for item in payload.get("assignment_ids") or [] if isinstance(item, str)]
        if not assignment_ids:
            raise HTTPException(status_code=400, detail="assignment_ids obbligatorio")

        plan_result = await db.execute(
            text(
                """
                INSERT INTO cat_route_plans
                  (cat_id, route_date, status, optimizer_version, metadata_json)
                VALUES
                  (:cat_id, :route_date, :status, 'dispatch-api-manual-v1', cast(:metadata_json as jsonb))
                RETURNING *
                """
            ),
            {
                "cat_id": payload.get("cat_id"),
                "route_date": payload.get("route_date"),
                "status": payload.get("status", "draft"),
                "metadata_json": _json_param(payload.get("metadata")),
            },
        )
        plan = _item(plan_result)
        if not plan:
            raise HTTPException(status_code=500, detail="Route plan non creato")

        assignments_result = await db.execute(
            text(
                """
                SELECT a.*, r.address_line, r.latitude, r.longitude, r.comune, r.provincia, r.priority
                FROM cat_assignments a
                JOIN dispatch_requests r ON r.id = a.dispatch_request_id
                WHERE a.cat_id = :cat_id AND a.id = ANY(:assignment_ids)
                ORDER BY a.scheduled_start ASC NULLS LAST, r.priority DESC
                """
            ),
            {"cat_id": payload.get("cat_id"), "assignment_ids": assignment_ids},
        )
        stops: list[dict[str, Any]] = []
        for index, assignment in enumerate(_items(assignments_result), start=1):
            stop_result = await db.execute(
                text(
                    """
                    INSERT INTO cat_route_stops
                      (route_plan_id, assignment_id, stop_order, scheduled_start, scheduled_end,
                       address_line, latitude, longitude, metadata_json)
                    VALUES
                      (:route_plan_id, :assignment_id, :stop_order, :scheduled_start, :scheduled_end,
                       :address_line, :latitude, :longitude, cast(:metadata_json as jsonb))
                    RETURNING *
                    """
                ),
                {
                    "route_plan_id": plan["id"],
                    "assignment_id": assignment["id"],
                    "stop_order": index,
                    "scheduled_start": assignment.get("scheduled_start"),
                    "scheduled_end": assignment.get("scheduled_end"),
                    "address_line": assignment.get("address_line"),
                    "latitude": assignment.get("latitude"),
                    "longitude": assignment.get("longitude"),
                    "metadata_json": _json_param({"comune": assignment.get("comune"), "provincia": assignment.get("provincia")}),
                },
            )
            stop = _item(stop_result)
            if stop:
                stops.append(stop)
                await db.execute(
                    text(
                        """
                        UPDATE cat_assignments
                        SET route_plan_id = :route_plan_id,
                            route_stop_id = :route_stop_id,
                            updated_at = now()
                        WHERE id = :assignment_id
                        """
                    ),
                    {"route_plan_id": plan["id"], "route_stop_id": stop["id"], "assignment_id": assignment["id"]},
                )
        await db.commit()
        return {"success": True, "route_plan": plan, "stops": stops}

    @classmethod
    async def dispatch_action(
        cls,
        db: AsyncSession,
        tenant_id: str,
        action: str,
        payload: dict[str, Any],
    ) -> dict[str, Any]:
        if action == "availability-rules":
            return await cls.replace_availability_rules(db, payload.get("cat_id"), payload.get("rules") or [])
        if action == "availability-overrides":
            return await cls.create_availability_override(db, payload)
        if action == "requests":
            return await cls.create_request(db, tenant_id, payload)
        if action == "insured-windows":
            return await cls.replace_insured_windows(db, payload)
        if action == "assignments":
            return await cls.create_assignment(db, payload)
        if action == "route-plans":
            return await cls.create_route_plan(db, payload)
        raise HTTPException(status_code=404, detail=f"CatDispatcher action not found: {action}")
