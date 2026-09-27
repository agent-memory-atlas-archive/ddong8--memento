"""Celery task: learn from the user's corrections every 10 minutes.

Nightly dreaming learns too, but a correction made at 10:00 shouldn't have to
wait until 03:00 (and for the user to publish a draft) to reach the AI tools.
"""

from __future__ import annotations

import asyncio
import logging

from sqlalchemy import select

from ..db.models import User
from ..db.session import async_session_factory
from ..services import ai_health
from ..services.correction_service import learn_from_corrections, summarize_new_topics
from ..services.notify_service import notify_user
from .celery_app import celery_app

logger = logging.getLogger("learning_tasks")

PUSH_COOLDOWN = 3600  # one "learned something" push per hour at most


async def _run() -> dict:
    async with async_session_factory() as db:
        users = (await db.execute(select(User).where(User.status == "active"))).scalars().all()
        totals = {"events": 0, "new_topics": 0}
        for user in users:
            try:
                result = await learn_from_corrections(db, user)
            except Exception as e:
                await db.rollback()
                logger.warning("Correction learning failed for user %s: %s", user.id, e)
                continue
            totals["events"] += result["events"]
            totals["new_topics"] += len(result["new_topics"])
            if result["new_topics"] and await ai_health.claim_alert(f"learned:{user.id}", PUSH_COOLDOWN):
                verb = "从最近 30 天里找到" if result["backfill"] else "刚学到"
                await notify_user(
                    user.id, "learning", f"Memento {verb}新的规矩",
                    summarize_new_topics(result["new_topics"]) + "。到「记忆库 → 常驻画像」确认后，各个 AI 工具下次同步就会用上。",
                )
        return totals


@celery_app.task(name="server.tasks.learning_tasks.learn_corrections", acks_late=True)
def learn_corrections() -> dict:
    try:
        return asyncio.run(_run())
    except Exception as e:
        logger.warning("learn_corrections errored: %s", e)
        return {"events": 0, "error": str(e)[:200]}
