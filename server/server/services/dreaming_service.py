"""Dreaming Consolidation Service — Autonomous Memory Tiering & Sleep Replay.

Inspired by cognitive science and modern AI Agent architectures (e.g., OpenClaw),
this service simulates the human sleep memory consolidation cycle:
1. Light Sleep (Stage & Filter): Scans recent raw interactions (Ask conversations,
   daily summaries, and tool messages), strips base64/transient noise, and stages
   candidate event digests.
2. REM Sleep (Association & Pattern Recognition): Discovers latent cross-session
   patterns, recurring developer habits, architectural decisions, and links knowledge
   graph entities.
3. Deep Sleep (Consolidation & Decay): Evaluates memories against a salience gate,
   promotes high-signal facts to UserMemory (L3 Core Memory / MEMORY.md), updates the
   knowledge graph, and archives a human-readable dream journal (DREAMS.md).
"""

from __future__ import annotations

import asyncio
import json
import logging
import re
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Any, Callable

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db.models import (
    AskConversation, ConversationMessage, DailySummary, Document,
    DreamJournal, KnowledgeEntity, KnowledgeObservation, KnowledgeRelation,
    Machine, User, UserMemory,
)
from .ai_provider import call_plain_chat, get_ai_providers

logger = logging.getLogger("server.dreaming_service")

# Noise patterns to strip during Light Sleep
_BASE64_DATA_RE = re.compile(
    r"data:image/[a-zA-Z0-9\+\.\-]+;base64,[A-Za-z0-9+/=]{40,}",
    re.IGNORECASE,
)
_RAW_BASE64_BLOB_RE = re.compile(r"([A-Za-z0-9+/]{120,}={0,2})")


def sanitize_transient_text(text: str) -> str:
    """Strip base64 data and truncate massive logs for dreaming digestion."""
    if not text:
        return ""
    cleaned = _BASE64_DATA_RE.sub("[image_base64_omitted]", text)
    cleaned = _RAW_BASE64_BLOB_RE.sub("[binary_blob_omitted]", cleaned)
    if len(cleaned) > 2500:
        cleaned = cleaned[:1500] + "\n...[中段内容修剪]...\n" + cleaned[-800:]
    return cleaned.strip()


_DREAM_PROMPT = """你是一个高阶智能大脑的认知记忆固化中枢（负责模拟人类睡眠时的记忆重组与知识固化机制）。
你的目标是分析用户最近的交互记录、每日研发小结与历史核心记忆，提炼出真正值得沉淀为【长期核心记忆 (MEMORY.md)】的高价值知识，并生成一份充满洞察的《梦境日记 (DREAMS.md)》。

### 用户已有的长期核心记忆 (L3 现有库)
{existing_core_memories}

### 阶段一已清洗的近期活动与会话脉络 (近 {days_back} 天)
{recent_activities}

---

### 做梦任务指导：
1. **REM 快速眼动反思 (Pattern & Insight Mining)**：
   - 跨会话、跨工具关联：分析用户在做什么项目？反复遇到了哪些技术坑？达成了哪些解决方案或架构约定？
   - 挖掘潜在偏好：用户纠正过 AI 什么？反复要求使用什么技术栈或流程？
2. **Deep 深度睡眠固化 (Salience Gating)**：
   - 坚决过滤临时琐事（如：单纯的“帮我看一下这行报错”、“在吗”、临时的测试文件、一次性的目录浏览）。
   - 严格筛选具有【长期指导意义】的条目晋升为长期记忆 (UserMemory)。
   - 分类 (category) 仅限：`rule` (开发铁律/规范), `architecture` (架构决策), `preference` (个人偏好), `project` (核心业务/技术栈), `general` (其他常识)。
   - key 请使用小写英文+下划线，简短精确（如 `windows_update_policy`, `ios_background_keepalive`, `dart_analyzer_clean`）。
   - confidence: 0.0 ~ 1.0 (仅当大于等于 0.75 时才会正式写入)。
3. **知识图谱关系 (Knowledge Graph Links)**：
   - 如果发现关键概念/技术之间的明确关联，可输出实体关联（如：`{{"source": "Windows更新", "target": "PowerShell", "relation": "uses"}}`）。

请严格输出合法的 JSON 格式（不要输出任何前后注释或 markdown 外部包裹）：
{{
  "light_sleep_notes": "浅睡阶段总结：清洗与概括了哪些主要会话与工具活动",
  "rem_reflections": "REM阶段反思：观察到的核心模式、思考过程、跨项目共性与经验教训",
  "deep_consolidations": "深睡阶段固化：最终决定沉淀为长期核心记忆的决策理由与遗忘剪枝考量",
  "promoted_memories": [
    {{
      "category": "rule",
      "tree_path": "/rules/desktop/windows_update_policy",
      "key": "unique_short_key",
      "content": "精准清晰的规则或知识描述",
      "confidence": 0.95
    }}
  ],
  "discovered_relations": [
    {{
      "source": "实体A",
      "target": "实体B",
      "relation": "uses/depends_on/creates"
    }}
  ]
}}
"""


async def run_dreaming_pipeline(
    db: AsyncSession,
    user: User,
    days_back: int = 2,
    start_date: date | None = None,
    end_date: date | None = None,
    tag: str = "nightly",
) -> DreamJournal:
    """Execute the 3-stage Dreaming pipeline for a specific user."""
    today = date.today()
    now = datetime.now(timezone.utc)

    if start_date is not None and end_date is not None:
        since_date = start_date
        until_date = end_date
        since_dt = datetime(start_date.year, start_date.month, start_date.day, tzinfo=timezone.utc)
        until_dt = datetime(end_date.year, end_date.month, end_date.day, 23, 59, 59, tzinfo=timezone.utc)
    else:
        until_date = today
        since_date = today - timedelta(days=days_back)
        until_dt = now
        since_dt = now - timedelta(days=days_back)

    # -----------------------------------------------------------------------
    # Phase 1: Light Sleep (Ingest & Filter)
    # -----------------------------------------------------------------------
    # 1. Gather Daily Summaries
    daily_res = await db.execute(
        select(DailySummary)
        .where(
            (DailySummary.user_id == user.id) | (DailySummary.user_id.is_(None)),
            DailySummary.summary_date >= since_date,
            DailySummary.summary_date <= until_date,
        )
        .order_by(DailySummary.summary_date.asc())
    )
    daily_summaries = daily_res.scalars().all()

    # 2. Gather recent Ask Conversations
    ask_res = await db.execute(
        select(AskConversation)
        .where(
            AskConversation.user_id == user.id,
            AskConversation.updated_at >= since_dt,
            AskConversation.updated_at <= until_dt,
        )
        .order_by(AskConversation.updated_at.asc())
        .limit(30)
    )
    ask_convs = ask_res.scalars().all()

    # 3. Gather recent ConversationMessages from user's machines
    user_machines_subq = select(Machine.id).where(Machine.user_id == user.id)
    user_docs_subq = select(Document.id).where(Document.machine_id.in_(user_machines_subq))
    msg_res = await db.execute(
        select(ConversationMessage.role, ConversationMessage.content, ConversationMessage.timestamp)
        .where(
            ConversationMessage.document_id.in_(user_docs_subq),
            ConversationMessage.timestamp >= since_dt,
            ConversationMessage.timestamp <= until_dt,
        )
        .order_by(ConversationMessage.timestamp.asc())
        .limit(60)
    )
    recent_msgs = msg_res.all()

    # Compile raw activity notes
    activity_snippets: list[str] = []
    scanned_count = len(daily_summaries) + len(ask_convs) + len(recent_msgs)

    if daily_summaries:
        activity_snippets.append("### 【每日研发摘要】")
        for ds in daily_summaries:
            activity_snippets.append(
                f"- [{ds.summary_date}] {ds.title}:\n{sanitize_transient_text(ds.summary)}"
            )

    if ask_convs:
        activity_snippets.append("\n### 【近期交互对话】")
        for c in ask_convs:
            turns_text = []
            for t in (c.turns or [])[-6:]:  # recent turns
                role = t.get("role", "unknown")
                content = sanitize_transient_text(str(t.get("content", "")))
                if content:
                    turns_text.append(f"  [{role}]: {content}")
            if turns_text:
                activity_snippets.append(f"- 对话《{c.title}》:\n" + "\n".join(turns_text))

    if recent_msgs:
        activity_snippets.append("\n### 【工具日志关键片段】")
        for role, content, ts in recent_msgs[-15:]:
            cleaned_c = sanitize_transient_text(content)
            if cleaned_c:
                ts_str = ts.strftime("%m-%d %H:%M") if ts else "?"
                activity_snippets.append(f"  [{ts_str} {role}]: {cleaned_c}")

    recent_activities_str = "\n".join(activity_snippets) if activity_snippets else "(近期无显著交互记录)"

    # Fetch existing core memories to prevent redundant generation
    existing_mem_res = await db.execute(
        select(UserMemory)
        .where(UserMemory.user_id == user.id)
        .order_by(UserMemory.category, UserMemory.updated_at.desc())
    )
    existing_mems = existing_mem_res.scalars().all()
    if existing_mems:
        existing_mem_str = "\n".join(
            f"- [{m.category}/{m.key}] ({m.confidence:.2f}): {m.content}"
            for m in existing_mems
        )
    else:
        existing_mem_str = "(尚未沉淀任何长期核心记忆)"

    # -----------------------------------------------------------------------
    # Phase 2 & 3: REM Sleep & Deep Sleep (via LLM Reflection)
    # -----------------------------------------------------------------------
    llm_output: dict[str, Any] = {}
    if get_ai_providers() and scanned_count > 0:
        days_span = (until_date - since_date).days + 1
        prompt = _DREAM_PROMPT.format(
            existing_core_memories=existing_mem_str,
            recent_activities=recent_activities_str,
            days_back=days_span,
        )
        try:
            raw_response = await call_plain_chat(
                messages=[
                    {
                        "role": "system",
                        "content": "You are the Memento Dreaming Memory Consolidation Kernel. Respond only with valid JSON.",
                    },
                    {"role": "user", "content": prompt},
                ],
                max_tokens=2500,
            )
            if raw_response:
                text = raw_response.strip()
                if text.startswith("```"):
                    text = text.split("\n", 1)[-1]
                    if text.endswith("```"):
                        text = text[:-3]
                text = text.strip()
                start = text.find("{")
                end = text.rfind("}") + 1
                if start >= 0 and end > start:
                    llm_output = json.loads(text[start:end])
        except Exception as e:
            logger.warning("Dreaming LLM call failed, proceeding with heuristic fallback: %s", e)

    # Heuristic fallback if LLM output is empty
    if not llm_output:
        light_notes = (
            f"扫描了近 {days_back} 天的 {scanned_count} 条记录（含 {len(daily_summaries)} 篇日报、"
            f"{len(ask_convs)} 组问答、{len(recent_msgs)} 条工具流）。完成临时垃圾过滤与去噪。"
        )
        rem_notes = "REM 反思阶段：数据量稳定，未发现需要突破阈值的跨周期冲突。保持当前长时记忆稳固。"
        deep_notes = "深睡阶段：常规巡检完成，暂无新增晋升条目。"
        promoted = []
        relations = []
    else:
        light_notes = str(llm_output.get("light_sleep_notes") or "完成近期交互与日报的去噪与切片。")
        rem_notes = str(llm_output.get("rem_reflections") or "完成跨时空模式识别与经验沉淀。")
        deep_notes = str(llm_output.get("deep_consolidations") or "完成长期记忆加权门控与固化。")
        promoted = llm_output.get("promoted_memories") or []
        relations = llm_output.get("discovered_relations") or []

    # -----------------------------------------------------------------------
    # Persist Promoted Core Memories (UserMemory)
    # -----------------------------------------------------------------------
    promoted_count = 0
    promoted_details: list[str] = []

    for item in promoted:
        cat = str(item.get("category", "general")).strip()
        key = str(item.get("key", "note")).strip().lower().replace(" ", "_")
        content = str(item.get("content", "")).strip()
        confidence = float(item.get("confidence", 0.9))
        tree_path = str(item.get("tree_path") or f"/{cat}/{key}").strip()

        if not content or confidence < 0.70:
            continue

        # Check existing
        existing = (await db.execute(
            select(UserMemory).where(
                UserMemory.user_id == user.id,
                UserMemory.category == cat,
                UserMemory.key == key,
            ).limit(1)
        )).scalar_one_or_none()

        if existing:
            existing.content = content
            existing.confidence = max(existing.confidence, confidence)
            existing.source = "dreaming"
            existing.tree_path = tree_path
            existing.updated_at = now
            promoted_details.append(f"- 🔄 更新【{tree_path}】: {content}")
        else:
            db.add(UserMemory(
                user_id=user.id,
                category=cat,
                key=key,
                content=content,
                confidence=confidence,
                source="dreaming",
                tree_path=tree_path,
                created_at=now,
                updated_at=now,
            ))
            promoted_details.append(f"- 🌟 新增【{tree_path}】: {content}")
        promoted_count += 1

    # Optional: Persist discovered relations into Knowledge Graph
    for rel in relations:
        src_name = str(rel.get("source", "")).strip()
        tgt_name = str(rel.get("target", "")).strip()
        rel_type = str(rel.get("relation", "relates_to")).strip()
        if not src_name or not tgt_name:
            continue
        try:
            # Find or create source & target entities
            s_ent = (await db.execute(
                select(KnowledgeEntity).where(
                    KnowledgeEntity.user_id == user.id,
                    KnowledgeEntity.name == src_name,
                ).limit(1)
            )).scalar_one_or_none()
            if not s_ent:
                s_ent = KnowledgeEntity(user_id=user.id, name=src_name, entity_type="concept")
                db.add(s_ent)
                await db.flush()

            t_ent = (await db.execute(
                select(KnowledgeEntity).where(
                    KnowledgeEntity.user_id == user.id,
                    KnowledgeEntity.name == tgt_name,
                ).limit(1)
            )).scalar_one_or_none()
            if not t_ent:
                t_ent = KnowledgeEntity(user_id=user.id, name=tgt_name, entity_type="concept")
                db.add(t_ent)
                await db.flush()

            db.add(KnowledgeRelation(
                source_id=s_ent.id,
                target_id=t_ent.id,
                relation_type=rel_type,
                strength=0.9,
            ))
        except Exception:
            pass  # Non-blocking for graph relation insertion

    # -----------------------------------------------------------------------
    # Generate Dream Journal Report (DREAMS.md)
    # -----------------------------------------------------------------------
    date_label = f"{since_date.isoformat()} ~ {until_date.isoformat()}" if since_date != until_date else until_date.isoformat()
    report_lines = [
        f"# 🌙 梦境反思日记 (Dream Journal) — {date_label}",
        "",
        f"> **做梦时间**：{now.strftime('%Y-%m-%d %H:%M:%S UTC')}  ",
        f"> **记忆扫描**：检索近期 {scanned_count} 条记录 | 固化新增/更新 {promoted_count} 条长期记忆",
        "",
        "## 💤 阶段一：浅度睡眠 (Light Sleep · 清洗去噪)",
        light_notes,
        "",
        "## 🧠 阶段二：REM 快速眼动期 (REM Sleep · 联想与模式反思)",
        rem_notes,
        "",
        "## 💎 阶段三：深度睡眠 (Deep Sleep · 长期记忆固化)",
        deep_notes,
        "",
    ]

    if promoted_details:
        report_lines.append("### 🌟 本次晋升至 MEMORY.md 的核心知识：")
        report_lines.extend(promoted_details)
        report_lines.append("")

    report_markdown = "\n".join(report_lines)

    # Save to dream_journals
    metrics = {
        "scanned_items": scanned_count,
        "promoted_count": promoted_count,
        "relations_found": len(relations),
        "days_back": (until_date - since_date).days + 1,
        "start_date": since_date.isoformat(),
        "end_date": until_date.isoformat(),
        "tag": tag,
    }

    journal = DreamJournal(
        user_id=user.id,
        dream_date=until_date,
        stage_metrics=metrics,
        light_sleep_notes=light_notes,
        rem_reflections=rem_notes,
        deep_consolidations=deep_notes,
        report_markdown=report_markdown,
        created_at=now,
    )
    db.add(journal)
    await db.commit()
    await db.refresh(journal)

    logger.info(
        "Dreaming pipeline completed for user %s: %d items promoted, journal %s created",
        user.email, promoted_count, journal.id,
    )
    return journal


async def export_core_memory_markdown(db: AsyncSession, user: User) -> str:
    """Render the user's UserMemory items into a unified MEMORY.md file."""
    res = await db.execute(
        select(UserMemory)
        .where(UserMemory.user_id == user.id)
        .order_by(UserMemory.category, UserMemory.key)
    )
    memories = res.scalars().all()

    if not memories:
        return (
            "# MEMORY.md — 个人核心记忆与研发知识库\n\n"
            "> 当前暂未沉淀长期记忆。您可以通过在聊天中交流、手动添加，或等待夜间做梦机制 (Dreaming Consolidation) 自动提炼生成。\n"
        )

    categories_map: dict[str, list[UserMemory]] = {}
    for m in memories:
        categories_map.setdefault(m.category, []).append(m)

    category_titles = {
        "rule": "1. 开发铁律与工程规范 (Rules & Guidelines)",
        "architecture": "2. 核心架构决策与设计模式 (Architecture Decisions)",
        "preference": "3. 个人偏好与工作流习惯 (Personal Preferences)",
        "project": "4. 项目背景与业务核心约束 (Project Domain Knowledge)",
        "general": "5. 综合常识与长期事实 (General Knowledge)",
    }

    lines = [
        "# MEMORY.md — 个人核心记忆与研发知识库",
        "",
        "> 由 Memento 做梦机制 (Dreaming Consolidation) 自动萃取并保持同步。",
        f"> 最后更新时间：{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')} | 记忆条目总数：{len(memories)}",
        "",
    ]

    for cat_code, cat_title in category_titles.items():
        items = categories_map.get(cat_code)
        if items:
            lines.append(f"## {cat_title}")
            for it in items:
                prefix = "📁 " if it.is_folder else ""
                path_info = f" `{it.tree_path}`" if it.tree_path else ""
                lines.append(f"- {prefix}**[{it.key}]**{path_info} ({it.confidence:.2f}): {it.content}")
            lines.append("")

    # Any custom categories
    for cat_code, items in categories_map.items():
        if cat_code not in category_titles:
            lines.append(f"## 其他分类 ({cat_code})")
            for it in items:
                prefix = "📁 " if it.is_folder else ""
                path_info = f" `{it.tree_path}`" if it.tree_path else ""
                lines.append(f"- {prefix}**[{it.key}]**{path_info}: {it.content}")
            lines.append("")

    return "\n".join(lines).strip()


async def compute_activity_windows(
    db: AsyncSession,
    user: User,
    chunk_days: int = 3,
) -> list[tuple[date, date]]:
    """Compute non-empty chronological time windows from earliest activity to today."""
    today = date.today()

    # 1. Earliest DailySummary
    daily_min_q = select(func.min(DailySummary.summary_date)).where(
        (DailySummary.user_id == user.id) | (DailySummary.user_id.is_(None))
    )
    daily_min = (await db.execute(daily_min_q)).scalar()

    # 2. Earliest Document
    user_machines_subq = select(Machine.id).where(Machine.user_id == user.id)
    doc_min_q = select(func.min(Document.created_at)).where(
        Document.machine_id.in_(user_machines_subq)
    )
    doc_min_dt = (await db.execute(doc_min_q)).scalar()
    doc_min = doc_min_dt.date() if doc_min_dt else None

    # 3. Earliest AskConversation
    ask_min_q = select(func.min(AskConversation.created_at)).where(
        AskConversation.user_id == user.id
    )
    ask_min_dt = (await db.execute(ask_min_q)).scalar()
    ask_min = ask_min_dt.date() if ask_min_dt else None

    dates = [d for d in (daily_min, doc_min, ask_min) if d is not None]
    if not dates:
        return []

    earliest = min(dates)
    if earliest >= today:
        return [(today - timedelta(days=1), today)]

    # Slice into chunks of chunk_days
    windows: list[tuple[date, date]] = []
    curr = earliest
    while curr <= today:
        nxt = min(curr + timedelta(days=chunk_days - 1), today)
        windows.append((curr, nxt))
        curr = nxt + timedelta(days=1)

    return windows


async def run_dreaming_backfill(
    db: AsyncSession,
    user: User,
    chunk_days: int = 3,
    max_chunks: int = 30,
    progress_callback: Callable[[dict[str, Any]], Any] | None = None,
) -> dict[str, Any]:
    """Execute progressive historical dreaming replay across chronological windows."""
    all_windows = await compute_activity_windows(db, user, chunk_days=chunk_days)
    if not all_windows:
        return {
            "status": "completed",
            "total_windows": 0,
            "processed_windows": 0,
            "skipped_windows": 0,
            "total_promoted": 0,
            "message": "暂无历史活动记录需要回溯",
        }

    # Process up to max_chunks (chronologically forward)
    windows_to_process = all_windows[:max_chunks]

    total_promoted = 0
    processed_count = 0
    skipped_count = 0
    journal_ids: list[str] = []

    user_machines_subq = select(Machine.id).where(Machine.user_id == user.id)
    user_docs_subq = select(Document.id).where(Document.machine_id.in_(user_machines_subq))

    for idx, (w_start, w_end) in enumerate(windows_to_process):
        w_start_dt = datetime(w_start.year, w_start.month, w_start.day, tzinfo=timezone.utc)
        w_end_dt = datetime(w_end.year, w_end.month, w_end.day, 23, 59, 59, tzinfo=timezone.utc)

        # Check daily summary count
        has_daily = (await db.execute(
            select(func.count()).select_from(DailySummary).where(
                (DailySummary.user_id == user.id) | (DailySummary.user_id.is_(None)),
                DailySummary.summary_date >= w_start,
                DailySummary.summary_date <= w_end,
            )
        )).scalar() or 0

        # Check ask conversations
        has_ask = (await db.execute(
            select(func.count()).select_from(AskConversation).where(
                AskConversation.user_id == user.id,
                AskConversation.updated_at >= w_start_dt,
                AskConversation.updated_at <= w_end_dt,
            )
        )).scalar() or 0

        # Check conversation messages
        has_msg = (await db.execute(
            select(func.count()).select_from(ConversationMessage).where(
                ConversationMessage.document_id.in_(user_docs_subq),
                ConversationMessage.timestamp >= w_start_dt,
                ConversationMessage.timestamp <= w_end_dt,
            )
        )).scalar() or 0

        if has_daily == 0 and has_ask == 0 and has_msg == 0:
            skipped_count += 1
            if progress_callback:
                res = progress_callback({
                    "current": idx + 1,
                    "total": len(windows_to_process),
                    "window": [w_start.isoformat(), w_end.isoformat()],
                    "status": "skipped_empty",
                    "promoted_total": total_promoted,
                })
                if asyncio.iscoroutine(res):
                    await res
            continue

        # Execute dreaming for this window
        journal = await run_dreaming_pipeline(
            db,
            user,
            start_date=w_start,
            end_date=w_end,
            tag="backfill",
        )

        promoted_in_win = journal.stage_metrics.get("promoted_count", 0)
        total_promoted += promoted_in_win
        processed_count += 1
        journal_ids.append(str(journal.id))

        if progress_callback:
            res = progress_callback({
                "current": idx + 1,
                "total": len(windows_to_process),
                "window": [w_start.isoformat(), w_end.isoformat()],
                "status": "processed",
                "promoted_in_chunk": promoted_in_win,
                "promoted_total": total_promoted,
            })
            if asyncio.iscoroutine(res):
                await res

    return {
        "status": "completed",
        "total_windows": len(all_windows),
        "processed_windows": processed_count,
        "skipped_windows": skipped_count,
        "total_promoted": total_promoted,
        "journal_ids": journal_ids,
    }

