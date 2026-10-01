"""Phone push settings (Bark)."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from ..db.models import User
from ..db.session import get_db
from ..middleware.auth import get_current_user
from ..services.notify_service import mask_push_url, parse_push_url, send_bark

router = APIRouter(prefix="/api/notify", tags=["notify"])


class NotifySettingsBody(BaseModel):
    bark_url: str | None = None  # "" clears it; None leaves it unchanged
    notify_risky: bool | None = None
    notify_task_done: bool | None = None
    notify_health: bool | None = None
    notify_learning: bool | None = None
    notify_todo: bool | None = None


def _settings_out(user: User) -> dict:
    prefs = user.notify_settings or {}
    device_tokens = prefs.get("device_tokens") or []
    return {
        "bark_configured": bool(prefs.get("bark_url")),
        "bark_masked": mask_push_url(prefs.get("bark_url")),
        "device_tokens_count": len(device_tokens),
        "native_configured": len(device_tokens) > 0,
        "notify_risky": prefs.get("notify_risky", True),
        "notify_task_done": prefs.get("notify_task_done", True),
        "notify_health": prefs.get("notify_health", True),
        "notify_learning": prefs.get("notify_learning", True),
        "notify_todo": prefs.get("notify_todo", True),
    }


@router.get("/settings")
async def get_settings(user: User = Depends(get_current_user)) -> dict:
    return _settings_out(user)


@router.put("/settings")
async def update_settings(
    body: NotifySettingsBody,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    prefs = dict(user.notify_settings or {})
    if body.bark_url is not None:
        raw = body.bark_url.strip()
        if not raw:
            prefs.pop("bark_url", None)
        elif not parse_push_url(raw):
            raise HTTPException(
                status_code=400,
                detail="不是有效的推送地址。iOS 请使用 https://api.day.app/Key，Android 请使用 https://ntfy.sh/Topic",
            )
        else:
            prefs["bark_url"] = raw
    if body.notify_risky is not None:
        prefs["notify_risky"] = body.notify_risky
    if body.notify_task_done is not None:
        prefs["notify_task_done"] = body.notify_task_done
    if body.notify_health is not None:
        prefs["notify_health"] = body.notify_health
    if body.notify_learning is not None:
        prefs["notify_learning"] = body.notify_learning
    if body.notify_todo is not None:
        prefs["notify_todo"] = body.notify_todo
    user.notify_settings = prefs
    await db.commit()
    return _settings_out(user)


class DeviceTokenBody(BaseModel):
    token: str
    platform: str | None = "mobile"


@router.post("/device-token")
async def register_device_token(
    body: DeviceTokenBody,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    """Register native mobile push token for Memento App."""
    tok = body.token.strip()
    if not tok:
        raise HTTPException(status_code=400, detail="Token cannot be empty")

    prefs = dict(user.notify_settings or {})
    tokens: list[str] = list(prefs.get("device_tokens") or [])
    if tok not in tokens:
        tokens.append(tok)
        prefs["device_tokens"] = tokens
        user.notify_settings = prefs
        await db.commit()
    return {"status": "ok", "registered": True, "device_tokens_count": len(tokens)}


@router.delete("/device-token")
async def unregister_device_token(
    body: DeviceTokenBody,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    """Unregister mobile push token upon sign-out."""
    tok = body.token.strip()
    prefs = dict(user.notify_settings or {})
    tokens: list[str] = list(prefs.get("device_tokens") or [])
    if tok in tokens:
        tokens.remove(tok)
        prefs["device_tokens"] = tokens
        user.notify_settings = prefs
        await db.commit()
    return {"status": "ok", "unregistered": True}


@router.post("/test")
async def send_test(user: User = Depends(get_current_user)) -> dict:
    prefs = user.notify_settings or {}
    bark_url = prefs.get("bark_url")
    device_tokens = prefs.get("device_tokens") or []

    if not bark_url and not device_tokens:
        raise HTTPException(status_code=400, detail="未检测到已绑定的 Memento 手机端或外部推送地址")

    from ..services.notify_service import send_expo_push
    sent = False

    if device_tokens:
        native_ok = await send_expo_push(
            device_tokens,
            "Memento 手机端原生测试通知",
            "恭喜！您的 Memento 移动端原生推送已完全通畅，无需借助任何第三方外部 App！",
        )
        if native_ok:
            sent = True

    if bark_url:
        bark_ok = await send_bark(
            bark_url,
            "Memento 测试通知",
            "收到这条说明推送已经通了。危险操作和任务完成都会推到这里。",
        )
        if bark_ok:
            sent = True

    if not sent:
        raise HTTPException(status_code=502, detail="推送发送失败，请检查网络或重新登录移动端")
    return {"ok": True, "native_mobile_sent": bool(device_tokens)}
