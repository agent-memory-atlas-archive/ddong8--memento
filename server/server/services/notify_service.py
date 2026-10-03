"""Phone push notifications via Bark (https://github.com/Finb/Bark).

The user pastes the push address the Bark app shows (https://api.day.app/<key>/...)
once; the server then pushes risky agent operations and finished tasks to it.
Everything here is fire-and-forget: a failed push is logged and never affects the
task that triggered it.
"""

from __future__ import annotations

import asyncio
import ipaddress
import logging
import socket
import uuid
from urllib.parse import urlparse

import httpx
from sqlalchemy import select

from ..config import settings
from ..db.models import User
from ..db.session import async_session_factory

logger = logging.getLogger("server.notify")

# Pushes per task for risky operations; beyond this they're recorded but not pushed,
# so a looping agent can't flood the phone.
RISKY_PUSHES_PER_TASK = 5
_risky_push_counts: dict[str, int] = {}
_background: set[asyncio.Task] = set()


def parse_push_url(raw: str | None) -> tuple[str, str, str] | None:
    """Parse a push endpoint into (provider, base_or_target_url, key_or_topic).
    
    Supported:
    - Bark (iOS): 'https://api.day.app/KEY[/anything]' -> ('bark', 'https://api.day.app', 'KEY')
    - ntfy (Android & multiplatform): 'https://ntfy.sh/TOPIC' -> ('ntfy', 'https://ntfy.sh/TOPIC', 'TOPIC')
    """
    if not raw:
        return None
    parsed = urlparse(raw.strip())
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        return None
    parts = [p for p in parsed.path.split("/") if p]
    if not parts:
        return None
    
    # Bark (official Bark endpoint requires https)
    if "api.day.app" in parsed.netloc:
        if parsed.scheme != "https":
            return None
        return "bark", f"https://{parsed.netloc}", parts[0]
    
    # ntfy (either ntfy.sh or self-hosted ntfy instance)
    if "ntfy" in parsed.netloc or len(parts) == 1:
        return "ntfy", f"{parsed.scheme}://{parsed.netloc}/{parts[0]}", parts[0]

    return "bark", f"{parsed.scheme}://{parsed.netloc}", parts[0]


def parse_bark_url(raw: str | None) -> tuple[str, str] | None:
    if not raw:
        return None
    parsed = urlparse(raw.strip())
    if parsed.scheme != "https":
        return None
    res = parse_push_url(raw)
    if not res:
        return None
    return res[1], res[2]


def mask_push_url(raw: str | None) -> str | None:
    res = parse_push_url(raw)
    if not res:
        return None
    provider, target, key = res
    if provider == "bark":
        return f"{target}/{key[:4]}…"
    # ntfy
    return f"{target[:-len(key)]}{key[:4]}…"


def mask_bark_url(raw: str | None) -> str | None:
    return mask_push_url(raw)


async def _is_public_host(host: str) -> bool:
    """Refuse to push to private/loopback/link-local addresses: the URL is user
    supplied, and the server must not be usable to probe its own network."""
    try:
        infos = await asyncio.to_thread(socket.getaddrinfo, host, 443)
    except OSError:
        return False
    for info in infos:
        ip = ipaddress.ip_address(info[4][0])
        if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast:
            return False
    return True


async def send_bark(
    push_url: str,
    title: str,
    body: str,
    *,
    url: str | None = None,
    level: str = "active",
) -> bool:
    """Send push notification supporting both Bark (iOS) and ntfy (Android/Universal)."""
    parsed = parse_push_url(push_url)
    if not parsed:
        return False
    provider, target, key = parsed
    host = urlparse(target).hostname or ""
    if not await _is_public_host(host):
        logger.warning("Push refused: %s does not resolve to a public address", host)
        return False

    if provider == "ntfy":
        # Send via ntfy (Android & multiplatform)
        headers = {
            "Title": title.encode("utf-8").decode("latin-1", "replace"),
            "Priority": "urgent" if level == "timeSensitive" else "default",
            "Tags": "robot,memento",
        }
        if url:
            headers["Click"] = url
        try:
            async with httpx.AsyncClient(timeout=10, follow_redirects=True) as client:
                resp = await client.post(target, content=body.encode("utf-8"), headers=headers)
            if resp.status_code not in (200, 201):
                logger.warning("ntfy push failed: HTTP %s %s", resp.status_code, resp.text[:200])
                return False
            return True
        except httpx.HTTPError as e:
            logger.warning("ntfy push failed: %s", e)
            return False

    # Default Bark (iOS)
    payload = {"device_key": key, "title": title, "body": body, "group": "Memento", "level": level}
    if url:
        payload["url"] = url
    try:
        async with httpx.AsyncClient(timeout=10, follow_redirects=False) as client:
            resp = await client.post(f"{target}/push", json=payload)
        if resp.status_code != 200:
            logger.warning("Bark push failed: HTTP %s %s", resp.status_code, resp.text[:200])
            return False
        return True
    except httpx.HTTPError as e:
        logger.warning("Bark push failed: %s", e)
        return False


def task_link(task_id: str) -> str | None:
    base = (settings.public_url or "").rstrip("/")
    return f"{base}/tasks/{task_id}" if base else None


async def send_expo_push(
    tokens: list[str],
    title: str,
    body: str,
    *,
    url: str | None = None,
    level: str = "active",
) -> bool:
    """Send native push notifications directly to the Memento mobile app via Expo Push service."""
    if not tokens:
        return False
    messages = [
        {
            "to": tok,
            "title": title,
            "body": body,
            "sound": "default",
            "priority": "high" if level == "timeSensitive" else "default",
            "data": {"url": url} if url else {},
            "_displayInForeground": True,
        }
        for tok in tokens
        if tok.startswith("ExponentPushToken") or tok.startswith("ExpoPushToken")
    ]
    if not messages:
        return False

    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.post(
                "https://exp.host/--/api/v2/push/send",
                json=messages,
                headers={"Accept": "application/json", "Accept-Encoding": "gzip, deflate", "Content-Type": "application/json"},
            )
        if resp.status_code != 200:
            logger.warning("Expo native push failed: HTTP %s %s", resp.status_code, resp.text[:200])
            return False

        data = resp.json()
        tickets = data.get("data") or []
        for ticket in tickets:
            if ticket.get("status") == "error":
                logger.warning("Expo Push delivery error: %s (%s)", ticket.get("message"), ticket.get("details"))
        return True
    except httpx.HTTPError as e:
        logger.warning("Expo native push failed: %s", e)
        return False


async def notify_user(
    user_id: uuid.UUID | str | None,
    kind: str,
    title: str,
    body: str,
    *,
    url: str | None = None,
) -> bool:
    """Push to the user's phone via native Memento app (or Bark/ntfy if configured).

    kind: "risky" (agent did something dangerous) | "task_done" (task finished
    while nobody was watching) | "health" (background AI jobs or nightly
    dreaming are failing) | "learning" (new corrections, skills or pitfalls learned) |
    "todo" (todos due today or overdue).
    """
    if not user_id:
        return False
    async with async_session_factory() as db:
        user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    prefs = (user.notify_settings or {}) if user else {}
    
    toggle = {
        "risky": "notify_risky", "health": "notify_health", "learning": "notify_learning", "todo": "notify_todo",
    }.get(kind, "notify_task_done")
    if not prefs.get(toggle, True):
        return False
    level = "timeSensitive" if kind == "risky" else "active"

    # Record to user's notification feed for real-time mobile synchronization
    item = {
        "id": str(uuid.uuid4()),
        "kind": kind,
        "title": title,
        "body": body,
        "url": url,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    try:
        async with async_session_factory() as db:
            db_user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
            if db_user:
                p = dict(db_user.notify_settings or {})
                feed = list(p.get("recent_notifications") or [])
                feed.insert(0, item)
                p["recent_notifications"] = feed[:30]
                db_user.notify_settings = p
                await db.commit()
    except Exception as e:
        logger.warning("Failed to record notification feed for user %s: %s", user_id, e)

    sent = True

    # 1. Native Memento Mobile App Push (No third-party app needed)
    device_tokens = prefs.get("device_tokens") or []
    if device_tokens:
        await send_expo_push(device_tokens, title, body, url=url, level=level)

    # 2. Bark / ntfy channel (if configured as secondary or fallback)
    if prefs.get("bark_url"):
        await send_bark(prefs["bark_url"], title, body, url=url, level=level)

    return sent


def allow_risky_push(task_id: str) -> bool:
    count = _risky_push_counts.get(task_id, 0)
    if count >= RISKY_PUSHES_PER_TASK:
        return False
    _risky_push_counts[task_id] = count + 1
    return True


def forget_task(task_id: str) -> None:
    _risky_push_counts.pop(task_id, None)


def spawn(coro) -> None:
    """Run a notification in the background, keeping a reference until it's done."""
    task = asyncio.create_task(coro)
    _background.add(task)
    task.add_done_callback(_background.discard)
