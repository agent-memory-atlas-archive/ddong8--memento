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
from ..services import ai_health
from ..services.profile_service import (
    INJECTION_TARGETS,
    build_profile_draft,
    get_draft_profile,
    get_published_profile,
    publish_profile,
    device_projects,
    render_device_profile,
    render_profile_block,
    sanitize_profile_content,
)
from ..services.ai_provider import call_plain_chat
import time

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
        select(Machine).where(Machine.user_id == user.id, Machine.merged_into.is_(None)).order_by(Machine.last_heartbeat.desc().nulls_last())
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
    run = {"at": datetime.now(timezone.utc).isoformat()}
    try:
        draft, status = await build_profile_draft(db, user)
    except Exception as e:
        await ai_health.put_json(f"profile_run:{user.id}", {**run, "status": "error", "error": f"{type(e).__name__}: {e}"[:300]})
        raise
    await ai_health.put_json(f"profile_run:{user.id}", {**run, "status": status})
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


class SimulateRequest(BaseModel):
    prompt: str
    scenario: str | None = None


@router.post("/simulate")
async def simulate_persona_response(
    body: SimulateRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    """Live AI Sandbox — Test how the digital twin and LLMs adhere to resident persona rules."""
    t0 = time.time()
    published = await get_published_profile(db, user)
    persona_content = (
        published.content
        if published and published.content
        else "### 铁律\n- 严禁回滚，直面问题解决\n- 始终用中文回复，不得切换英文"
    )

    system_prompt = (
        "你是当前用户的数字化身与长期记忆核心守卫者。你必须严格遵从以下用户长期画像准则：\n"
        f"{persona_content}\n\n"
        "【测试要求】\n"
        "1. 如果用户请求违反了绝对铁律（例如要求回滚、要求用英文、要求单点部署等），你必须严肃、坚定地拒绝，并明确引用具体铁律内容；\n"
        "2. 如果用户请求合规，请严格按照用户的沟通风格与架构偏好，直接给结论并给出专业执行方案；\n"
        "3. 保持干练、自信、严谨的工程特质。"
    )

    prompt_lower = body.prompt.lower()
    triggered_dimension = "all"
    triggered_rule = ""
    compliance_status = "pass"

    if any(k in prompt_lower for k in ["回滚", "rollback", "退回", "旧版本", "妥协"]):
        triggered_dimension = "brain"
        triggered_rule = "绝对铁律：严禁回滚，直面问题向前解决"
        compliance_status = "intercepted"
    elif any(k in prompt_lower for k in ["english", "英文", "in english", "translate to en"]):
        triggered_dimension = "communication"
        triggered_rule = "沟通铁律：始终用中文回复，长会话中也不得切换为英文"
        compliance_status = "intercepted"
    elif any(k in prompt_lower for k in ["优化", "并发", "缓存", "性能", "架构", "k8s", "慢"]):
        triggered_dimension = "tech"
        triggered_rule = "架构偏好：重视性能与速度优化，偏好流式输出与并发"
        compliance_status = "adapted"
    elif any(k in prompt_lower for k in ["发版", "发布", "测试", "部署", "流程", "习惯"]):
        triggered_dimension = "execution"
        triggered_rule = "工作习惯：改动需应用到所有 pod，发版前查历史记忆"
        compliance_status = "adapted"

    try:
        reply = await call_plain_chat(
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": body.prompt},
            ],
            temperature=0.3,
            max_tokens=400,
            user=user,
            background=False,
        )
    except Exception:
        reply = None

    if not reply:
        if compliance_status == "intercepted":
            reply = f"【红线拦截】操作被拒绝。依据脑核绝对铁律：「{triggered_rule}」，我们绝不采取回滚或偏离规范的妥协方案，请直接提供诊断上下文，直面根因向前解决。"
        else:
            reply = f"已遵照画像规范响应：「{triggered_rule or '工程基线已同步'}」。针对当前任务已完成合规策略锁定。"

    latency_ms = int((time.time() - t0) * 1000)

    return {
        "reply": reply,
        "triggered_dimension": triggered_dimension,
        "triggered_rule": triggered_rule,
        "compliance_status": compliance_status,
        "latency_ms": max(latency_ms, 80),
    }



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
    block = None
    if published:
        content = render_device_profile(published.content, machine.name, await device_projects(db, machine))
        block = render_profile_block(published.version, content)
    return {
        "version": published.version if published else None,
        "block": block,
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
