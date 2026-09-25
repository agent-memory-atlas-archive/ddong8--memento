"""Resident profile API — review/publish in the web UI, pull from collectors."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db.models import Machine, User, UserProfile
from ..db.session import get_db
from ..middleware.auth import get_current_user, verify_collector_token
from ..services.profile_service import (
    INJECTION_TARGETS,
    build_profile_draft,
    get_draft_profile,
    get_published_profile,
    publish_profile,
    render_profile_block,
    sanitize_profile_content,
)

router = APIRouter(prefix="/api/profile", tags=["profile"])

ONLINE_WINDOW = timedelta(seconds=180)


class ProfileContent(BaseModel):
    content: str


class PublishBody(BaseModel):
    content: str | None = None  # publish this text instead of the stored draft


class TargetsBody(BaseModel):
    targets: list[str]


class InjectionReport(BaseModel):
    version: int | None = None
    results: dict[str, str]


def _profile_out(p: UserProfile | None) -> dict | None:
    if p is None:
        return None
    return {
        "id": str(p.id),
        "status": p.status,
        "version": p.version,
        "content": p.content,
        "stats": p.stats or {},
        "updated_at": p.updated_at.isoformat() if p.updated_at else None,
        "published_at": p.published_at.isoformat() if p.published_at else None,
    }


async def _owned_machine(db: AsyncSession, user: User, device_id: str) -> Machine:
    machine = (await db.execute(
        select(Machine).where(Machine.collector_token_hash == device_id, Machine.user_id == user.id)
    )).scalars().first()
    if machine is None:
        raise HTTPException(status_code=404, detail="device not found")
    return machine


# ---------------------------------------------------------------------------
# Web UI (JWT)
# ---------------------------------------------------------------------------

@router.get("")
async def get_profile(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    published = await get_published_profile(db, user)
    draft = await get_draft_profile(db, user)
    history = (await db.execute(
        select(UserProfile.version, UserProfile.published_at)
        .where(UserProfile.user_id == user.id, UserProfile.status == "published")
        .order_by(UserProfile.version.desc())
        .limit(10)
    )).all()
    machines = (await db.execute(
        select(Machine).where(Machine.user_id == user.id).order_by(Machine.last_heartbeat.desc().nulls_last())
    )).scalars().all()
    now = datetime.now(timezone.utc)
    return {
        "published": _profile_out(published),
        "draft": _profile_out(draft),
        "history": [
            {"version": v, "published_at": ts.isoformat() if ts else None} for v, ts in history
        ],
        "targets": list(INJECTION_TARGETS),
        "devices": [
            {
                "device_id": m.collector_token_hash,
                "name": m.name,
                "online": bool(m.last_heartbeat and now - m.last_heartbeat < ONLINE_WINDOW),
                "targets": m.profile_targets or [],
                "status": m.profile_status or {},
            }
            for m in machines
        ],
    }


@router.post("/draft/regenerate")
async def regenerate_draft(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    draft, status = await build_profile_draft(db, user)
    return {"status": status, "draft": _profile_out(draft)}


@router.put("/draft")
async def save_draft(
    body: ProfileContent,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    content = sanitize_profile_content(body.content)
    if not content:
        raise HTTPException(status_code=400, detail="content is empty")
    draft = await get_draft_profile(db, user)
    if draft:
        draft.content = content
        draft.stats = {**(draft.stats or {}), "edited_by_user": True}
    else:
        draft = UserProfile(user_id=user.id, status="draft", content=content, stats={"edited_by_user": True})
        db.add(draft)
    await db.commit()
    await db.refresh(draft)
    return {"draft": _profile_out(draft)}


@router.delete("/draft")
async def discard_draft(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    draft = await get_draft_profile(db, user)
    if draft:
        await db.delete(draft)
        await db.commit()
    return {"status": "discarded"}


@router.post("/publish")
async def publish(
    body: PublishBody,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    content = body.content
    if content is None:
        draft = await get_draft_profile(db, user)
        if draft is None:
            raise HTTPException(status_code=400, detail="no draft to publish")
        content = draft.content
    try:
        profile = await publish_profile(db, user, content)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return {"published": _profile_out(profile)}


@router.put("/devices/{device_id}/targets")
async def set_device_targets(
    device_id: str,
    body: TargetsBody,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    unknown = sorted(set(body.targets) - set(INJECTION_TARGETS))
    if unknown:
        raise HTTPException(status_code=400, detail=f"unknown targets: {', '.join(unknown)}")
    machine = await _owned_machine(db, user, device_id)
    machine.profile_targets = [t for t in INJECTION_TARGETS if t in body.targets]
    await db.commit()
    return {"device_id": device_id, "targets": machine.profile_targets}


# ---------------------------------------------------------------------------
# Collector (X-Collector-Token + X-Device-Id)
# ---------------------------------------------------------------------------

@router.get("/injection")
async def get_injection(
    x_device_id: str = Header(..., alias="X-Device-Id"),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(verify_collector_token),
) -> dict:
    """What this device should have in each tool's instruction file.

    An empty target list tells the collector to remove any block it wrote earlier,
    so turning a tool off in the web UI cleans up on the next poll.
    """
    machine = await _owned_machine(db, user, x_device_id)
    published = await get_published_profile(db, user)
    return {
        "version": published.version if published else None,
        "block": render_profile_block(published.version, published.content) if published else None,
        "targets": machine.profile_targets or [],
    }


@router.post("/injection/status")
async def report_injection(
    body: InjectionReport,
    x_device_id: str = Header(..., alias="X-Device-Id"),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(verify_collector_token),
) -> dict:
    machine = await _owned_machine(db, user, x_device_id)
    machine.profile_status = {
        "version": body.version,
        "results": {k: str(v)[:200] for k, v in body.results.items() if k in INJECTION_TARGETS},
        "reported_at": datetime.now(timezone.utc).isoformat(),
    }
    await db.commit()
    return {"status": "ok"}
