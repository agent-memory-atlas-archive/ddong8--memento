"""Manually triggered long jobs (review now, run the evaluation) with a status the app can poll."""

from __future__ import annotations

import logging
from collections.abc import Awaitable, Callable
from datetime import datetime, timedelta, timezone
from typing import Any

from . import ai_health
from .notify_service import spawn

logger = logging.getLogger("server.jobs")

STALE = timedelta(minutes=45)  # a "running" job older than this died with its pod


def _key(name: str, user_id: Any) -> str:
    return f"job:{name}:{user_id}"


async def status(name: str, user_id: Any) -> dict[str, Any] | None:
    return await ai_health.get_json(_key(name, user_id))


async def start(name: str, user_id: Any, work: Callable[[], Awaitable[Any]]) -> dict[str, Any]:
    """Run `work` in the background unless the same job is already running for this user."""
    key = _key(name, user_id)
    now = datetime.now(timezone.utc)
    current = await ai_health.get_json(key)
    if current and current.get("status") == "running":
        started = datetime.fromisoformat(current["started_at"])
        if now - started < STALE:
            return {**current, "already_running": True}
    state = {"status": "running", "started_at": now.isoformat()}
    await ai_health.put_json(key, state)
    spawn(_run(key, state, work))
    return state


async def _run(key: str, state: dict[str, Any], work: Callable[[], Awaitable[Any]]) -> None:
    try:
        result = await work()
        await ai_health.put_json(key, {
            **state, "status": "done", "finished_at": datetime.now(timezone.utc).isoformat(), "result": result,
        })
    except Exception as e:
        logger.warning("job %s failed: %s", key, e)
        await ai_health.put_json(key, {
            **state, "status": "error", "finished_at": datetime.now(timezone.utc).isoformat(),
            "error": f"{type(e).__name__}: {e}"[:300],
        })
