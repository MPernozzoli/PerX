"""
Tasks routes
"""
from datetime import datetime
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db
from app.core.security import get_current_active_user
from app.models.case_task import CaseTask
from app.models.claim import Claim
from app.models.user import User
from pydantic import BaseModel

router = APIRouter()


class TaskCreateRequest(BaseModel):
    title: str
    description: str | None = None
    type: str = "generic"
    priority: str = "normal"
    sinistroRef: str | None = None
    dueDate: datetime | None = None
    assignedTo: str | None = None
    createdBy: str | None = None


class TaskUpdateRequest(BaseModel):
    title: str | None = None
    description: str | None = None
    priority: str | None = None
    dueDate: datetime | None = None
    status: str | None = None


class TaskResponse(BaseModel):
    id: str
    title: str
    description: str | None = None
    type: str
    priority: str
    status: str
    sinistroRef: str | None = None
    dueDate: datetime | None = None
    assignedTo: str | None = None
    createdBy: str | None = None
    createdAt: datetime
    completedAt: datetime | None = None


def _priority_to_int(priority: str | None) -> int:
    match (priority or "normal").lower():
        case "low":
            return 20
        case "high":
            return 80
        case "urgent":
            return 100
        case _:
            return 50


def _priority_to_string(priority: int) -> str:
    if priority >= 90:
        return "urgent"
    if priority >= 70:
        return "high"
    if priority <= 25:
        return "low"
    return "normal"


def _status_to_client(status: str) -> str:
    if status == "done":
        return "completed"
    return status


async def _serialize_task(db: AsyncSession, task: CaseTask) -> TaskResponse:
    claim_ref = None
    assigned_to_email = None
    created_by_email = None

    claim = await db.get(Claim, task.claim_id)
    if claim:
        claim_ref = claim.external_ref

    if task.assignee_user_id:
        assignee = await db.get(User, task.assignee_user_id)
        assigned_to_email = assignee.email if assignee else None

    creator = await db.get(User, task.created_by_user_id)
    created_by_email = creator.email if creator else None

    return TaskResponse(
        id=task.id,
        title=task.title,
        description=task.description,
        type=task.type or "generic",
        priority=_priority_to_string(task.priority),
        status=_status_to_client(task.status),
        sinistroRef=claim_ref,
        dueDate=task.due_date,
        assignedTo=assigned_to_email,
        createdBy=created_by_email,
        createdAt=task.created_at,
        completedAt=task.completed_at,
    )


@router.get("/tasks", response_model=list[TaskResponse])
async def list_tasks(
    sinistro_ref: str | None = Query(None, alias="sinistroRef"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """List tasks for the current user or a specific claim reference."""
    query = select(CaseTask).where(CaseTask.tenant_id == current_user.tenant_id)

    if sinistro_ref:
        claim_result = await db.execute(
            select(Claim).where(
                Claim.tenant_id == current_user.tenant_id,
                Claim.external_ref == sinistro_ref
            )
        )
        claim = claim_result.scalar_one_or_none()
        if not claim:
            return []
        query = query.where(CaseTask.claim_id == claim.id)
    else:
        query = query.where(
            (CaseTask.assignee_user_id == current_user.id) |
            (CaseTask.created_by_user_id == current_user.id)
        )

    result = await db.execute(query.order_by(CaseTask.due_date.asc().nullslast(), CaseTask.created_at.desc()))
    tasks = result.scalars().all()
    return [await _serialize_task(db, task) for task in tasks]


@router.post("/tasks", response_model=TaskResponse, status_code=status.HTTP_201_CREATED)
async def create_task(
    request: TaskCreateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    """Create a task, optionally linked to a claim reference."""
    if not request.sinistroRef:
        raise HTTPException(status_code=400, detail="sinistroRef is required")

    claim_result = await db.execute(
        select(Claim).where(
            Claim.tenant_id == current_user.tenant_id,
            Claim.external_ref == request.sinistroRef
        )
    )
    claim = claim_result.scalar_one_or_none()
    if not claim:
        raise HTTPException(status_code=404, detail="Claim not found")
    claim_id = claim.id

    assignee_user_id = None
    if request.assignedTo:
        assignee_result = await db.execute(
            select(User).where(
                User.tenant_id == current_user.tenant_id,
                User.email == request.assignedTo
            )
        )
        assignee = assignee_result.scalar_one_or_none()
        if not assignee:
            raise HTTPException(status_code=404, detail="Assigned user not found")
        assignee_user_id = assignee.id

    task = CaseTask(
        id=str(uuid.uuid4()),
        tenant_id=current_user.tenant_id,
        claim_id=claim_id,
        title=request.title,
        description=request.description,
        status="open",
        assignee_user_id=assignee_user_id,
        created_by_user_id=current_user.id,
        due_date=request.dueDate,
        completed_at=None,
        priority=_priority_to_int(request.priority),
        type=request.type,
        metadata_json=None,
    )
    db.add(task)
    await db.commit()
    await db.refresh(task)
    return await _serialize_task(db, task)


@router.put("/tasks/{task_id}", response_model=TaskResponse)
async def update_task(
    task_id: str,
    request: TaskUpdateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    query = select(CaseTask).where(
        CaseTask.id == task_id,
        CaseTask.tenant_id == current_user.tenant_id
    )
    result = await db.execute(query)
    task = result.scalar_one_or_none()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    if request.title is not None:
        task.title = request.title
    if request.description is not None:
        task.description = request.description
    if request.priority is not None:
        task.priority = _priority_to_int(request.priority)
    if request.dueDate is not None:
        task.due_date = request.dueDate
    if request.status is not None:
        task.status = "done" if request.status == "completed" else request.status
        task.completed_at = datetime.utcnow() if task.status == "done" else None

    await db.commit()
    await db.refresh(task)
    return await _serialize_task(db, task)


@router.post("/tasks/{task_id}/complete", response_model=TaskResponse)
async def complete_task(
    task_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    query = select(CaseTask).where(
        CaseTask.id == task_id,
        CaseTask.tenant_id == current_user.tenant_id
    )
    result = await db.execute(query)
    task = result.scalar_one_or_none()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    task.status = "done"
    task.completed_at = datetime.utcnow()
    await db.commit()
    await db.refresh(task)
    return await _serialize_task(db, task)
