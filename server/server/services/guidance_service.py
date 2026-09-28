"""What an AI should know before it acts: the user's rules, past pitfalls, and learned skills.

Shared by the MCP rule check and Memento's own agent, so both see the same
answer. Everything returned counts as recalled.
"""

from __future__ import annotations

import re
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db.models import Skill, User, UserMemory
from .memory_lifecycle import ALWAYS_ON, touch_recalled

# Action words the AI tends to use in English, mapped to how the user writes about them.
_ACTION_SYNONYMS: dict[str, tuple[str, ...]] = {
    "deploy": ("部署", "上线", "发布", "k8s", "kubectl", "fleet", "pod"),
    "release": ("发版", "发布", "版本", "tag", "release"),
    "migration": ("迁移", "数据库", "表", "schema", "migration"),
    "db": ("数据库", "表", "postgres", "sql"),
    "build": ("构建", "编译", "打包", "build", "镜像"),
    "push": ("推送", "提交", "push", "git"),
    "commit": ("提交", "commit", "git"),
    "git": ("git", "提交", "分支"),
    "test": ("测试", "test"),
    "config": ("配置", "config", "设置"),
    "update": ("更新", "升级", "update"),
    "delete": ("删除", "清理", "rm"),
    "backup": ("备份", "backup"),
    "data": ("数据", "表", "标注"),
    "refactor": ("重构", "refactor"),
    "install": ("安装", "依赖", "install"),
}

RULES_LIMIT = 10
PITFALL_LIMIT = 8
SKILL_LIMIT = 3


def terms_for(*texts: str | None) -> list[str]:
    """Lower-cased search terms from the action and any free text, with synonyms."""
    from .tokenize import _segment  # jieba, loaded lazily

    raw: list[str] = []
    for text in texts:
        if not text:
            continue
        for word in re.split(r"[\s_\-/,，;；]+", text.lower()):
            if word:
                raw.append(word)
                raw.extend(_ACTION_SYNONYMS.get(word, ()))
        raw.extend(t.lower() for t in _segment(text))
    seen: list[str] = []
    for term in raw:
        term = term.strip()
        if len(term) < 2 and not re.match(r"[一-鿿]", term):
            continue
        if term not in seen:
            seen.append(term)
    return seen[:40]


def score(text: str, terms: list[str]) -> int:
    low = (text or "").lower()
    return sum(1 for t in terms if t in low)


def _project_of(mem: UserMemory) -> str | None:
    parts = (mem.tree_path or "").strip("/").split("/")
    return parts[1].lower() if len(parts) >= 3 and parts[0] in ("pitfall", "project") else None


async def guidance_for(
    db: AsyncSession,
    user: User,
    action: str | None,
    project: str | None = None,
    query: str | None = None,
) -> dict[str, Any]:
    """Rules, pitfalls and skills relevant to doing `action` (in `project`, about `query`)."""
    terms = terms_for(action, query)
    proj = (project or "").strip().lower() or None

    memories = (await db.execute(
        select(UserMemory).where(
            UserMemory.user_id == user.id,
            UserMemory.status == "active",
            UserMemory.is_folder.is_(False),
            UserMemory.category.in_((*ALWAYS_ON, "pitfall", "project", "architecture")),
        )
    )).scalars().all()

    rules: list[tuple[int, UserMemory]] = []
    pitfalls: list[tuple[int, UserMemory]] = []
    for mem in memories:
        text = f"{mem.key} {mem.tree_path or ''} {mem.content}"
        s = score(text, terms)
        mem_proj = _project_of(mem)
        in_project = bool(proj and (mem_proj == proj or proj in (mem.tree_path or "").lower()))
        if mem.category in ALWAYS_ON:
            # Matching ones, plus what the user approved by hand (those always apply).
            if s or mem.source == "manual":
                rules.append((s, mem))
        elif mem.category == "pitfall":
            if s or in_project:
                pitfalls.append((s + (3 if in_project else 0), mem))
        elif in_project and s:
            rules.append((s, mem))

    def best(items: list[tuple[int, UserMemory]], n: int) -> list[UserMemory]:
        items.sort(key=lambda x: (x[0], x[1].source == "manual", x[1].updated_at), reverse=True)
        return [m for _, m in items[:n]]

    chosen_rules = best(rules, RULES_LIMIT)
    chosen_pitfalls = best(pitfalls, PITFALL_LIMIT)

    skills = (await db.execute(
        select(Skill).where(Skill.user_id == user.id, Skill.status == "published")
    )).scalars().all()
    ranked_skills = sorted(
        ((score(f"{s.slug} {s.title} {s.description} {s.project or ''}", terms)
          + (3 if proj and (s.project or "").lower() == proj else 0), s) for s in skills),
        key=lambda x: x[0], reverse=True,
    )
    chosen_skills = [s for sc, s in ranked_skills if sc > 0][:SKILL_LIMIT]

    await touch_recalled(m.id for m in chosen_rules + chosen_pitfalls)
    return {
        "action": action,
        "project": project,
        "rules": [memory_out(m) for m in chosen_rules],
        "pitfalls": [memory_out(m) for m in chosen_pitfalls],
        "skills": [{"slug": s.slug, "title": s.title, "description": s.description} for s in chosen_skills],
    }


def memory_out(mem: UserMemory) -> dict[str, Any]:
    return {
        "id": str(mem.id),
        "category": mem.category,
        "key": mem.key,
        "content": mem.content,
        "source": mem.source,
        "tree_path": mem.tree_path,
    }


def render_guidance(g: dict[str, Any]) -> str:
    """Markdown for an AI to read."""
    head = f"# 执行「{g.get('action') or '操作'}」前的检查" + (f"（项目：{g['project']}）" if g.get("project") else "")
    lines = [head]
    if g["rules"]:
        lines.append("\n## 必须遵守的规矩")
        lines += [f"- {m['content']}" for m in g["rules"]]
    if g["pitfalls"]:
        lines.append("\n## 以前踩过的坑")
        lines += [f"- {m['content']}" for m in g["pitfalls"]]
    if g["skills"]:
        lines.append("\n## 可以直接照做的技能")
        lines += [f"- `{s['slug']}` {s['title']}：{s['description']}" for s in g["skills"]]
    if len(lines) == 1:
        lines.append("\n没有找到相关的规矩或踩坑记录，按常规做法进行。")
    return "\n".join(lines)
