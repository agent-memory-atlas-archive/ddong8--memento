"""Corrections the user made to AIs: confirm what Memento learned, see if it sticks."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db.models import CorrectionEvent, CorrectionTopic, User
from ..db.session import get_db
from ..middleware.auth import get_current_user
from ..services.correction_service import ProfileFull, accept_topic, correction_stats, topic_out
from ..services.profile_service import PROFILE_MAX_CHARS

router = APIRouter(prefix="/api/learning", tags=["learning"])


class AcceptBody(BaseModel):
    statement: str | None = None  # the user's edit; None keeps what was learned


async def _own_topic(db: AsyncSession, user: User, topic_id: str) -> CorrectionTopic:
    try:
        tid = uuid.UUID(topic_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="not found")
    topic = await db.get(CorrectionTopic, tid)
    if topic is None or topic.user_id != user.id:
        raise HTTPException(status_code=404, detail="not found")
    return topic


@router.get("/corrections")
async def list_corrections(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    pending = (await db.execute(
        select(CorrectionTopic)
        .where(CorrectionTopic.user_id == user.id, CorrectionTopic.status == "pending")
        .order_by(CorrectionTopic.times.desc(), CorrectionTopic.last_at.desc())
        .limit(30)
    )).scalars().all()
    out = []
    for topic in pending:
        quotes = (await db.execute(
            select(CorrectionEvent).where(CorrectionEvent.topic_id == topic.id)
            .order_by(CorrectionEvent.said_at.desc()).limit(3)
        )).scalars().all()
        out.append(topic_out(topic, quotes))
    return {"pending": out, "stats": await correction_stats(db, user)}


@router.post("/corrections/{topic_id}/accept")
async def accept(
    topic_id: str,
    body: AcceptBody,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    topic = await _own_topic(db, user, topic_id)
    try:
        topic = await accept_topic(db, user, topic, body.statement)
    except ProfileFull:
        raise HTTPException(
            status_code=409,
            detail=f"常驻画像已接近 {PROFILE_MAX_CHARS} 字上限，先在画像里删减一些再采纳。",
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return {"topic": topic_out(topic)}


@router.post("/corrections/{topic_id}/dismiss")
async def dismiss(
    topic_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    topic = await _own_topic(db, user, topic_id)
    topic.status = "dismissed"
    await db.commit()
    return {"topic": topic_out(topic)}
