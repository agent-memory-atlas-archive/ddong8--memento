"""Celery task for Nightly Dreaming Consolidation."""

from __future__ import annotations

import asyncio
import logging
from datetime import date

from sqlalchemy import select

from ..db.models import User
from ..db.session import async_session_factory
from ..services.dreaming_service import run_dreaming_pipeline
from .celery_app import celery_app

logger = logging.getLogger("server.tasks.dreaming_tasks")


async def _run_all_users_dreaming(days_back: int = 1) -> dict[str, int]:
    """Run dreaming consolidation for all active users."""
    async with async_session_factory() as db:
        res = await db.execute(
            select(User).where(User.status == "active")
        )
        users = res.scalars().all()
        processed = 0
        errors = 0

        for user in users:
            try:
                await run_dreaming_pipeline(db, user, days_back=days_back)
                processed += 1
            except Exception as e:
                logger.error("Dreaming failed for user %s (%s): %s", user.id, user.email, e)
                errors += 1

        return {"processed": processed, "errors": errors}


@celery_app.task(
    name="server.tasks.dreaming_tasks.run_nightly_dreaming",
    autoretry_for=(Exception,),
    max_retries=2,
    retry_backoff=True,
    retry_backoff_max=300,
    acks_late=True,
)
def run_nightly_dreaming(days_back: int = 1) -> dict[str, int]:
    """Execute nightly dreaming memory consolidation across all users."""
    logger.info("Starting nightly dreaming consolidation (days_back=%d)...", days_back)
    return asyncio.run(_run_all_users_dreaming(days_back=days_back))
