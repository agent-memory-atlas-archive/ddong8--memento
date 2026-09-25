"""Celery task for Nightly Dreaming Consolidation."""

from __future__ import annotations

import asyncio
import logging
from datetime import date

from sqlalchemy import select

from ..db.models import User
from ..db.session import async_session_factory
from ..services.dreaming_service import run_dreaming_backfill, run_dreaming_pipeline
from ..services.profile_service import build_profile_draft

try:
    from .celery_app import celery_app
except (ImportError, ModuleNotFoundError):
    class _DummyCelery:
        def task(self, *args, **kwargs):
            def decorator(fn):
                fn.delay = fn
                return fn
            return decorator
    celery_app = _DummyCelery()

logger = logging.getLogger("server.tasks.dreaming_tasks")

_BACKFILL_STATUS: dict[str, dict] = {}


def get_backfill_status(user_id: str) -> dict:
    """Get the current progress or latest result of a user's dreaming backfill."""
    return _BACKFILL_STATUS.get(user_id, {"status": "idle"})


def set_backfill_status(user_id: str, status: dict) -> None:
    """Update backfill status in-memory."""
    _BACKFILL_STATUS[user_id] = status


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
                await db.rollback()
                errors += 1

            # Refresh the resident-profile draft. It only reaches AI tools once
            # the user publishes it, so a bad night can't spread anywhere.
            try:
                await build_profile_draft(db, user)
            except Exception as e:
                logger.warning("Profile draft failed for user %s: %s", user.id, e)
                await db.rollback()

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


async def run_user_backfill_async(user_id: str, chunk_days: int = 3, max_chunks: int = 30) -> dict:
    """Execute backfill asynchronously for a single user."""
    import uuid
    set_backfill_status(user_id, {
        "status": "running",
        "current": 0,
        "total": 0,
        "promoted_total": 0,
        "message": "正在初始化时间切片与历史活动探测...",
    })
    async with async_session_factory() as db:
        u_uuid = uuid.UUID(user_id) if isinstance(user_id, str) else user_id
        user = (await db.execute(select(User).where(User.id == u_uuid))).scalar_one_or_none()
        if not user:
            set_backfill_status(user_id, {"status": "error", "error": "User not found"})
            return {"error": "User not found"}

        def on_progress(p: dict):
            set_backfill_status(user_id, {
                "status": "running",
                "current": p.get("current", 0),
                "total": p.get("total", 0),
                "window": p.get("window", []),
                "window_status": p.get("status", ""),
                "promoted_total": p.get("promoted_total", 0),
            })

        try:
            result = await run_dreaming_backfill(
                db,
                user,
                chunk_days=chunk_days,
                max_chunks=max_chunks,
                progress_callback=on_progress,
            )
            set_backfill_status(user_id, {
                "status": "completed",
                "result": result,
            })
            return result
        except Exception as e:
            logger.error("Dreaming backfill failed for user %s: %s", user_id, e)
            set_backfill_status(user_id, {
                "status": "error",
                "error": str(e),
            })
            raise


@celery_app.task(
    name="server.tasks.dreaming_tasks.run_dreaming_backfill_task",
    acks_late=True,
)
def run_dreaming_backfill_task(user_id: str, chunk_days: int = 3, max_chunks: int = 30) -> dict:
    """Execute historical dreaming backfill for a user in background."""
    logger.info("Starting historical dreaming backfill for user %s (chunk_days=%d)...", user_id, chunk_days)
    return asyncio.run(run_user_backfill_async(user_id, chunk_days=chunk_days, max_chunks=max_chunks))

