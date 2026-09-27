"""System health overview: is the learning loop actually working?

Pulls together AI call outcomes (Redis counters), nightly dreaming, the
resident profile and its sync to devices, and the ingest pipeline's retry
backlog, then turns them into a short list of problems worth a look.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db.models import Document, DreamJournal, Machine, User, UserProfile
from . import ai_health
from .correction_service import correction_stats

ONLINE_WINDOW = timedelta(seconds=180)  # same as the profile page
DREAM_STALE = timedelta(hours=30)  # nightly at 03:00, plus slack
BACKLOG_WARN = 20


def ai_failing(last_hour: dict[str, Any]) -> bool:
    """Enough calls failed outright in the last hour to be worth a push."""
    calls = last_hour["calls"]
    return calls["failed"] >= 3 and calls["failed"] / max(calls["total"], 1) >= 0.2


def top_reasons(stats: dict[str, Any], n: int = 2) -> str:
    labels = [r["label"] for r in stats.get("reasons", []) if r["reason"] != "reasoning_retry"][:n]
    return "、".join(labels)


def assess(
    ai: dict[str, Any],
    last_hour: dict[str, Any],
    dreaming: dict[str, Any],
    profile: dict[str, Any],
    pipeline: dict[str, Any],
    now: datetime,
    learning: dict[str, Any] | None = None,
) -> list[dict[str, str]]:
    """Problems worth showing, most severe first. Each: {level, area, text}."""
    issues: list[dict[str, str]] = []

    def add(level: str, area: str, text: str) -> None:
        issues.append({"level": level, "area": area, "text": text})

    calls = ai["calls"]
    reasons = top_reasons(ai)
    if not ai.get("available", True):
        add("warn", "ai", "读不到 AI 调用统计（Redis 不可用）")
    if ai_failing(last_hour):
        lc = last_hour["calls"]
        add("error", "ai", f"最近 1 小时 {lc['failed']}/{lc['total']} 次 AI 调用失败" + (f"，主要原因：{top_reasons(last_hour)}" if top_reasons(last_hour) else ""))
    elif calls["failed"] >= 5 and calls["failed"] / max(calls["total"], 1) >= 0.05:
        add("warn", "ai", f"24 小时内 {calls['failed']} 次 AI 调用所有模型都没答上" + (f"，主要原因：{reasons}" if reasons else ""))
    if calls["fallback"] >= 5 and calls["fallback"] / max(calls["total"], 1) >= 0.3:
        add("warn", "ai", f"首选模型不稳定：24 小时内 {calls['fallback']} 次靠备用模型才完成")

    last_run = dreaming.get("last_run")
    if last_run and not last_run.get("ok", True):
        add("error", "dreaming", f"上次做梦失败：{last_run.get('error', '未知错误')}")
    latest = dreaming.get("journals", [])[:1]
    latest_at = datetime.fromisoformat(latest[0]["created_at"]) if latest else None
    if latest_at is None or now - latest_at > DREAM_STALE:
        add("warn", "dreaming", "超过 30 小时没有新的做梦记录" if latest_at else "还没有做梦记录")
    if last_run and last_run.get("profile_status") in ("llm_failed", "error"):
        add("warn", "profile", "夜间画像草稿生成失败")

    manual = profile.get("last_run")
    if manual and manual.get("status") in ("llm_failed", "error"):
        add("warn", "profile", "上次手动生成画像失败")
    broken = [d["name"] for d in profile.get("devices", []) if d["errors"]]
    if broken:
        add("warn", "profile", f"{len(broken)} 台设备写入画像出错：{'、'.join(broken[:3])}")

    if learning and learning.get("learned_repeat_7d", 0) >= 2:
        add("warn", "learning", f"最近 7 天有 {learning['learned_repeat_7d']} 次纠正的是已经学会的规矩，"
                                "说明它没传到 AI 那里（画像没发布，或设备没开启写入）")

    if pipeline["knowledge_failed"] >= BACKLOG_WARN:
        add("warn", "pipeline", f"{pipeline['knowledge_failed']} 篇文档知识图谱抽取失败，等待重试")
    if pipeline["embedding_failed"] >= BACKLOG_WARN:
        add("warn", "pipeline", f"{pipeline['embedding_failed']} 篇文档向量化失败，等待重试")

    issues.sort(key=lambda i: 0 if i["level"] == "error" else 1)
    return issues


async def _dreaming(db: AsyncSession, user: User) -> dict[str, Any]:
    journals = (await db.execute(
        select(DreamJournal)
        .where(DreamJournal.user_id == user.id)
        .order_by(DreamJournal.created_at.desc())
        .limit(7)
    )).scalars().all()
    rows = []
    for j in journals:
        m = j.stage_metrics or {}
        voice = m.get("user_voice") or {}
        rows.append({
            "date": j.dream_date.isoformat(),
            "created_at": j.created_at.isoformat(),
            "scanned": m.get("scanned_items", 0),
            "promoted": m.get("promoted_count", 0),
            "relations": m.get("relations_found", 0),
            "voice": voice.get("kept"),
        })
    return {"journals": rows, "last_run": await ai_health.get_json(f"dreaming:{user.id}")}


async def _profile(db: AsyncSession, user: User, now: datetime) -> dict[str, Any]:
    rows = (await db.execute(
        select(UserProfile).where(UserProfile.user_id == user.id).order_by(UserProfile.created_at.desc())
    )).scalars().all()
    published = max((r for r in rows if r.status == "published"), key=lambda r: r.version or 0, default=None)
    draft = next((r for r in rows if r.status == "draft"), None)

    machines = (await db.execute(select(Machine).where(Machine.user_id == user.id))).scalars().all()
    devices = []
    for m in machines:
        if not m.profile_targets:
            continue
        status = m.profile_status or {}
        results = status.get("results") or {}
        devices.append({
            "name": m.name,
            "online": bool(m.last_heartbeat and now - m.last_heartbeat < ONLINE_WINDOW),
            "targets": list(m.profile_targets),
            "version": status.get("version"),
            "reported_at": status.get("reported_at"),
            "synced": published is not None and status.get("version") == published.version,
            "errors": [t for t, r in results.items() if str(r).startswith("error")],
        })
    return {
        "published": {
            "version": published.version,
            "published_at": (published.published_at or published.created_at).isoformat(),
        } if published else None,
        "draft": {"updated_at": (draft.updated_at or draft.created_at).isoformat()} if draft else None,
        "last_run": await ai_health.get_json(f"profile_run:{user.id}"),
        "devices": devices,
    }


async def _pipeline(db: AsyncSession, user: User) -> dict[str, int]:
    row = (await db.execute(
        select(
            func.count().filter(Document.embedding_status == "failed"),
            func.count().filter(Document.knowledge_status == "failed"),
        )
        .select_from(Document)
        .join(Machine, Document.machine_id == Machine.id)
        .where(Machine.user_id == user.id)
    )).one()
    return {"embedding_failed": row[0] or 0, "knowledge_failed": row[1] or 0}


async def _devices(db: AsyncSession, user: User, now: datetime) -> dict[str, int]:
    beats = (await db.execute(select(Machine.last_heartbeat).where(Machine.user_id == user.id))).scalars().all()
    return {"total": len(beats), "online": sum(1 for b in beats if b and now - b < ONLINE_WINDOW)}


async def build_overview(db: AsyncSession, user: User) -> dict[str, Any]:
    now = datetime.now(timezone.utc)
    ai = await ai_health.summary(24)
    last_hour = await ai_health.summary(1)
    dreaming = await _dreaming(db, user)
    profile = await _profile(db, user, now)
    pipeline = await _pipeline(db, user)
    devices = await _devices(db, user, now)
    learning = await correction_stats(db, user)
    issues = assess(ai, last_hour, dreaming, profile, pipeline, now, learning)
    level = "error" if any(i["level"] == "error" for i in issues) else ("warn" if issues else "ok")
    return {
        "generated_at": now.isoformat(),
        "level": level,
        "issues": issues,
        "ai": ai,
        "dreaming": dreaming,
        "profile": profile,
        "pipeline": pipeline,
        "devices": devices,
        "learning": learning,
    }
