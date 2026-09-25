"""Resident profile — the short "about me" block every AI tool loads at session start.

Built from what the user actually typed (the user-voice stage shared with dreaming)
plus their preference/rule core memories, then held as a draft until the user
publishes it. Collectors write only published text, between the begin/end markers,
into each enabled tool's global instruction file (CLAUDE.md, AGENTS.md, ...).
"""

from __future__ import annotations

import logging
import re
from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db.models import User, UserMemory, UserProfile
from .ai_provider import call_plain_chat, get_ai_providers
from .dreaming_service import fetch_user_voice_rows, plan_user_voice_batches, render_user_voice

logger = logging.getLogger("server.profile_service")

PROFILE_MAX_CHARS = 1800
PROFILE_VOICE_DAYS = 30
# Tools whose global instruction file a collector can carry the block in.
# Cursor keeps its global rules in a settings database, not a file, so it isn't here.
INJECTION_TARGETS = ("claude_code", "codex", "antigravity", "openclaw", "hermes")

# The collector matches these same markers (mobile/lib/collector/services/profile_inject_service.dart).
PROFILE_BEGIN = "<!-- memento:begin"
PROFILE_END = "<!-- memento:end -->"
PROFILE_BLOCK_RE = re.compile(r"<!-- memento:begin[^>]*-->[\s\S]*?<!-- memento:end -->\n?")

_PROFILE_PROMPT = """你在为一位用户维护一段"常驻画像"。它会在用户每次打开 Claude Code、Codex、Gemini 等 AI 工具时自动加载，让 AI 一开始就知道该怎么和这位用户协作。

## 当前已发布的画像
{current}

## 用户最近 {days} 天亲口说的话（只含用户本人输入）
{voice}

## 用户的偏好与铁律类长期记忆
{memories}

## 要求
- 在当前画像基础上增删改，不要无故重写。已有条目除非被新证据推翻，否则保留。
- 只写能指导 AI 行为的内容：沟通方式、必须遵守的规则、工作习惯、技术偏好。不写项目细节、提交哈希、文件路径、一次性任务。
- 每条都必须能在上面的原话或记忆里找到依据；只在一次随口的话里出现过的，不写。
- 直接对 AI 下指令的祈使句（如"始终用中文回复"），不要写成"用户喜欢……"。
- Markdown，按这几个小标题分组，没有内容的小标题省略：### 沟通、### 铁律、### 工作方式、### 技术偏好。每条一行，以"- "开头。
- 总长度不超过 {max_chars} 个字符。
- 只输出画像正文，不要解释、前言或代码块包裹。"""


def strip_profile_block(text: str) -> str:
    """Remove an injected profile block, so collecting a tool's instruction file
    never feeds Memento its own output back as something to learn from."""
    if not text or PROFILE_BEGIN not in text:
        return text
    return PROFILE_BLOCK_RE.sub("", text)


def sanitize_profile_content(text: str | None) -> str:
    """Normalize LLM or user-edited profile text into something safe to inject."""
    if not text:
        return ""
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.split("\n", 1)[-1]
        if cleaned.rstrip().endswith("```"):
            cleaned = cleaned.rstrip()[:-3]
    # HTML comment delimiters would let the text forge or close the managed block.
    cleaned = cleaned.replace("<!--", "").replace("-->", "").strip()
    if len(cleaned) > PROFILE_MAX_CHARS:
        cut = cleaned.rfind("\n", 0, PROFILE_MAX_CHARS)
        cleaned = cleaned[: cut if cut > 0 else PROFILE_MAX_CHARS].rstrip()
    return cleaned


def render_profile_block(version: int, content: str) -> str:
    """The exact text a collector writes into a tool's instruction file."""
    return (
        f"{PROFILE_BEGIN} v{version} · 由 Memento 生成，请在 Memento 中修改，手改此段会被覆盖 -->\n"
        "## 关于我（Memento 长期记忆）\n\n"
        f"{content.strip()}\n\n"
        "需要更多上下文时，用 memento-memory MCP 的 memory_search / memory_core 查询。\n"
        f"{PROFILE_END}\n"
    )


async def get_published_profile(db: AsyncSession, user: User) -> UserProfile | None:
    return (await db.execute(
        select(UserProfile)
        .where(UserProfile.user_id == user.id, UserProfile.status == "published")
        .order_by(UserProfile.version.desc())
        .limit(1)
    )).scalar_one_or_none()


async def get_draft_profile(db: AsyncSession, user: User) -> UserProfile | None:
    return (await db.execute(
        select(UserProfile)
        .where(UserProfile.user_id == user.id, UserProfile.status == "draft")
        .order_by(UserProfile.updated_at.desc())
        .limit(1)
    )).scalar_one_or_none()


async def publish_profile(db: AsyncSession, user: User, content: str) -> UserProfile:
    """Freeze content as the next published version and drop the pending draft."""
    content = sanitize_profile_content(content)
    if not content:
        raise ValueError("profile content is empty")
    last = (await db.execute(
        select(func.max(UserProfile.version)).where(UserProfile.user_id == user.id)
    )).scalar() or 0
    draft = await get_draft_profile(db, user)
    now = datetime.now(timezone.utc)
    if draft:
        draft.status = "published"
        draft.version = last + 1
        draft.content = content
        draft.published_at = now
        profile = draft
    else:
        profile = UserProfile(
            user_id=user.id, status="published", version=last + 1,
            content=content, stats={"source": "manual"}, published_at=now,
        )
        db.add(profile)
    await db.commit()
    await db.refresh(profile)
    return profile


async def _profile_memories(db: AsyncSession, user: User) -> list[UserMemory]:
    rows = (await db.execute(
        select(UserMemory)
        .where(
            UserMemory.user_id == user.id,
            UserMemory.category.in_(("preference", "rule", "rules")),
            UserMemory.is_folder.is_(False),
        )
        .order_by(UserMemory.updated_at.desc())
        .limit(120)
    )).scalars().all()
    # Hand-written entries first; among the rest, the ones dreaming is surest about.
    return sorted(rows, key=lambda m: (m.source != "manual", -(m.confidence or 0)))[:60]


async def build_profile_draft(db: AsyncSession, user: User) -> tuple[UserProfile | None, str]:
    """Refresh the user's draft profile.

    Returns (draft, "updated"), or (None, reason) with reason one of: "no_llm",
    "user_editing", "no_input", "llm_failed", "same_as_published".
    """
    if not get_ai_providers():
        return None, "no_llm"

    draft = await get_draft_profile(db, user)
    if draft and (draft.stats or {}).get("edited_by_user"):
        return None, "user_editing"  # never clobber an edit the user hasn't published yet

    now = datetime.now(timezone.utc)
    voice_rows = await fetch_user_voice_rows(db, user, now - timedelta(days=PROFILE_VOICE_DAYS), now)
    batches, voice_stats = plan_user_voice_batches(voice_rows)
    voice = await render_user_voice(batches)
    memories = await _profile_memories(db, user)
    published = await get_published_profile(db, user)

    if not voice and not memories:
        return None, "no_input"

    memory_lines = "\n".join(f"- [{m.category}] {m.content.strip()[:200]}" for m in memories)
    raw = await call_plain_chat(
        messages=[
            {"role": "system", "content": "You maintain a concise user profile for AI assistants. Output only the profile body."},
            {"role": "user", "content": _PROFILE_PROMPT.format(
                current=published.content if published else "（尚无）",
                days=PROFILE_VOICE_DAYS,
                voice=voice or "（无）",
                memories=memory_lines or "（无）",
                max_chars=PROFILE_MAX_CHARS,
            )},
        ],
        max_tokens=1500,
    )
    content = sanitize_profile_content(raw)
    if not content:
        return None, "llm_failed"
    if published and content == published.content.strip():
        return None, "same_as_published"

    stats = {"user_voice": voice_stats, "memories": len(memories), "generated_at": now.isoformat()}
    if draft:
        draft.content = content
        draft.stats = stats
    else:
        draft = UserProfile(user_id=user.id, status="draft", content=content, stats=stats)
        db.add(draft)
    await db.commit()
    await db.refresh(draft)
    return draft, "updated"
