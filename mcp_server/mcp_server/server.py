"""MCP Memory Server — exposes personal AI memory via Model Context Protocol.

Calls the Memento server's REST API with the user's token (--server + --token,
or the local collector's config). The TypeScript port in packages/mcp is what
the desktop app ships; this package stays for existing pip installs.
"""

from __future__ import annotations

import logging
from datetime import date, timedelta

from mcp.server.fastmcp import FastMCP

logger = logging.getLogger("mcp_memory")

mcp = FastMCP(
    "Memento",
    instructions=(
        "Personal AI memory — search conversations, recall knowledge, explore project context from your Memento data. "
        "Before deploying, releasing, migrating a database, deleting or changing data, pushing, or changing config, "
        "call memory_check_rule: it returns the user's iron rules, pitfalls hit before on similar work, and skills to follow. "
        "After a failure whose cause you found and fixed, call memory_pitfall. When the user says to do something later, "
        "call todo_add; when asked what's left, call todo_list."
    ),
)

# Initialized on startup
_remote = None  # RemoteClient


def init_server(server_url: str, token: str, token_loader=None):
    """Initialize the MCP server against a Memento server."""
    global _remote
    if not server_url or not token:
        raise ValueError("--server and --token are required")
    from .remote_client import RemoteClient
    _remote = RemoteClient(server_url, token, token_loader=token_loader)
    logger.info("MCP Memory Server initialized: %s", server_url)


# ---------------------------------------------------------------------------
# Tools
#
# Mental grouping:
#   - find: memory_search / memory_recall / memory_context
#   - write: memory_store
#   - overview: daily_summary
#   - drill-in: memory_open / memory_conversation / memory_graph
# ---------------------------------------------------------------------------

@mcp.tool()
async def memory_search(
    query: str,
    limit: int = 5,
    tool_filter: str | None = None,
    days: int | None = None,
) -> str:
    """Search your personal AI memory using semantic + full-text hybrid search.

    Use this to find past conversations, decisions, solutions, and knowledge
    from all your AI tools (Claude Code, Cursor, Codex, Windsurf, etc.).

    Args:
        query: Natural language search query
        limit: Max results to return (default 5)
        tool_filter: Optional tool filter (claude_code, codex, cursor, antigravity, openclaw, obsidian)
        days: Optional time filter — only search last N days
    """
    try:
        results = await _remote.search(
            query, limit=limit, tool_filter=tool_filter, days=days,
        )
    except Exception as e:
        return f"Search failed: {e}"
    if not results:
        return "No matching memories found."
    parts = []
    for i, r in enumerate(results, 1):
        title = r.get('title') or r.get('relative_path', 'Untitled')
        snippet = r.get('snippet', '') or ''
        parts.append(
            f"## Result {i}: {title} ({r.get('tool_id', '')})\n"
            f"**Source**: {r.get('relative_path', '')}\n"
            f"**Date**: {(r.get('synced_at') or '')[:10]}\n\n"
            f"{snippet}\n"
        )
    return "\n---\n\n".join(parts)


@mcp.tool()
async def memory_recall(
    category: str = "conversation",
    project: str | None = None,
    days: int = 7,
    limit: int = 10,
    date: str | None = None,
) -> str:
    """Recall recent memories by category, project, and optional date.

    Args:
        category: Memory category (conversation, memory, identity, plan, config, learning, skill, note)
        project: Optional project name filter
        days: How far back to look (default 7 days, ignored if date given)
        limit: Max items to return
        date: Optional specific date (YYYY-MM-DD), overrides days
    """
    # If specific date given, use daily endpoint
    if date:
        try:
            data = await _remote.get_daily(date)
            conversations = data.get("overview", {}).get("conversations", [])
            if not conversations:
                return f"No conversations on {date}."
            parts = [f"# Conversations on {date}\n"]
            for c in conversations[:limit]:
                title = c.get("title") or c.get("id", "")[:8]
                u = c.get("user_messages", 0)
                a = c.get("assistant_messages", 0)
                parts.append(f"- [{c.get('tool_id', '')}] **{title}** ({u}↑ {a}↓)")
            return "\n".join(parts)
        except Exception as e:
            return f"Could not load conversations for {date}: {e}"

    # Otherwise use search-style: list recent files of category
    try:
        tools = await _remote.get_tools()
    except Exception as e:
        return f"Failed to list tools: {e}"

    from datetime import datetime as _dt
    cutoff_str = (_dt.utcnow() - timedelta(days=days)).isoformat()
    all_files = []
    for tool in tools:
        try:
            files = await _remote.get_tool_files(tool.get("id", ""), category=category)
            for f in files:
                f["_tool_id"] = tool.get("id", "")
                all_files.append(f)
        except Exception:
            continue

    # Filter by date and project; drop subagent noise (.meta.json sidecars
    # and .resolved transient files) which pollute recent-conversation lists.
    def _noise(path: str) -> bool:
        p = path or ""
        return p.endswith(".meta.json") or ".resolved" in p
    filtered = [
        f for f in all_files
        if (f.get("synced_at") or "") >= cutoff_str
        and not _noise(f.get("relative_path", ""))
    ]
    if project:
        filtered = [f for f in filtered if project.lower() in (f.get("relative_path") or "").lower()]

    # Sort by synced_at desc
    filtered.sort(key=lambda f: f.get("synced_at", ""), reverse=True)

    if not filtered:
        return f"No {category} memories in last {days} days."

    parts = [f"# Recent {category} (last {days} days)\n"]
    for f in filtered[:limit]:
        title = f.get("title") or f.get("relative_path", "")
        d = (f.get("synced_at") or "")[:10]
        parts.append(f"- [{f['_tool_id']}] **{title}** — {d}")
    return "\n".join(parts)


@mcp.tool()
async def memory_context(project_name: str) -> str:
    """Get project context — meta + the FULL CONTENT of curated docs
    (identity / memory / plan / learning / note), plus a list of recent
    conversations. Conversation bodies are not inlined (they can be MB
    each) — use `memory_conversation(doc_id)` to drill into one, or
    `memory_blueprint(project_name)` for the kitchen sink including
    knowledge-graph context.

    Args:
        project_name: Project name to look up (fuzzy ilike match)
    """
    projects = await _remote.list_projects()
    matched = [p for p in projects if project_name.lower() in (p.get("title", "") or "").lower()]
    if not matched:
        return f"No project found matching '{project_name}'."
    # include_content=True so the docs that ARE worth inlining come
    # back inline; saves the AI an N+1 memory_open round-trip.
    project = await _remote.get_project(matched[0]["id"], include_content=True)
    parts = [f"# Project: {project.get('title', project_name)}"]
    parts.append(f"**Tool**: {project.get('tool_id', '')}")
    if project.get("source_path"):
        parts.append(f"**Path**: `{project['source_path']}`")

    def _noise(d: dict) -> bool:
        p = d.get("relative_path", "") or ""
        return p.endswith(".meta.json") or ".resolved" in p
    docs = [d for d in project.get("documents", []) if not _noise(d)]

    # Split into "inline-able" (have a 'content' key from include_content)
    # vs conversation-style (metadata only).
    inlined = [d for d in docs if d.get("content")]
    listed = [d for d in docs if not d.get("content")]

    if inlined:
        parts.append(f"\n## Curated documents ({len(inlined)})")
        for d in inlined:
            title = d.get("title") or d.get("relative_path", "")
            parts.append(f"\n### [{d.get('category', '')}] {title}")
            parts.append(f"*{d.get('relative_path', '')}*")
            if d.get("ai_summary"):
                parts.append(f"\n**AI summary**: {d['ai_summary']}")
            parts.append("")
            parts.append(d["content"])
    if listed:
        parts.append(f"\n## Other documents ({len(listed)})")
        for d in listed[:20]:
            title = d.get("title") or d.get("relative_path", "")
            parts.append(f"- [{d.get('category', '')}] {title} — `{d.get('id', '')}`")
    return "\n".join(parts)


@mcp.tool()
async def memory_blueprint(project_name: str, recent_conversations: int = 10) -> str:
    """One-shot project blueprint — everything you need to bring a fresh
    AI session up to speed on a project in a single tool call.

    Returns: project meta + FULL content of identity / memory / plan /
    learning files + recent conversations' AI summaries + every related
    knowledge-graph entity with its observations and outgoing relations.

    Use this at the START of a new session when you want maximum
    context with minimum tool calls. For follow-up drills, use
    `memory_open(doc_id)`, `memory_conversation(doc_id)`,
    `memory_graph(entity_name)`, or `memory_search(query)`.

    Args:
        project_name: Project name (fuzzy match)
        recent_conversations: How many recent conversation titles + AI
            summaries to include (default 10; set 0 to omit)
    """
    try:
        projects = await _remote.list_projects()
    except Exception as e:
        return f"Failed to list projects: {e}"
    matched = [p for p in projects if project_name.lower() in (p.get("title", "") or "").lower()]
    if not matched:
        return f"No project found matching '{project_name}'."
    try:
        bp = await _remote.get_project_blueprint(matched[0]["id"], recent_convs=recent_conversations)
    except Exception as e:
        return f"Blueprint fetch failed: {e}"

    proj = bp.get("project", {})
    counts = bp.get("counts", {})
    out: list[str] = []
    out.append(f"# Blueprint — {proj.get('title', project_name)}")
    out.append(f"**Tool**: `{proj.get('tool_id', '')}`  ·  "
               f"**Path**: `{proj.get('source_path', '') or '?'}`")
    out.append(f"_curated={counts.get('curated_docs', 0)} · "
               f"recent_convs={counts.get('recent_conversations', 0)} · "
               f"entities={counts.get('entities', 0)} · "
               f"observations={counts.get('total_observations', 0)}_")
    out.append("")

    # ── Curated docs ───────────────────────────────────────────
    curated = bp.get("curated_docs", [])
    if curated:
        out.append("## Curated documents")
        for d in curated:
            title = d.get("title") or d.get("relative_path", "")
            out.append(f"\n### [{d.get('category', '')}] {title}")
            out.append(f"*{d.get('relative_path', '')}*  ·  *{(d.get('synced_at') or '')[:10]}*")
            if d.get("ai_summary"):
                out.append(f"\n**AI summary**: {d['ai_summary']}")
            out.append("")
            out.append(d.get("content") or "*(empty)*")
        out.append("")

    # ── Knowledge graph ────────────────────────────────────────
    kg = bp.get("knowledge_graph", {})
    entities = kg.get("entities", [])
    if entities:
        out.append("## Knowledge graph")
        for e in entities:
            out.append(f"\n### {e.get('name')} ({e.get('entity_type', '')})")
            if e.get("summary"):
                out.append(e["summary"])
            rels = e.get("relations", [])
            if rels:
                out.append("\n**Relations:**")
                for r in rels:
                    out.append(f"- {r.get('relation', '')} → **{r.get('target_name', '')}** "
                               f"({r.get('target_type', '')})")
            obs = e.get("observations", [])
            if obs:
                out.append("\n**Observations:**")
                for o in obs:
                    date_str = (o.get("observed_at") or "")[:10]
                    prefix = f"[{date_str}] " if date_str else ""
                    out.append(f"- {prefix}{o.get('content', '')}")
        out.append("")

    # ── Recent conversations ───────────────────────────────────
    convs = bp.get("recent_conversations", [])
    if convs:
        out.append("## Recent conversations")
        for c in convs:
            date_str = (c.get("synced_at") or "")[:10]
            title = c.get("title", "Untitled")
            out.append(f"\n### {title} ({date_str}, {c.get('tool_id', '')})")
            out.append(f"_doc id: `{c.get('id', '')}`  ·  call `memory_conversation(doc_id)` for full text_")
            if c.get("ai_summary"):
                out.append("")
                out.append(c["ai_summary"])

    return "\n".join(out)


@mcp.tool()
async def memory_store(
    content: str,
    entity_name: str | None = None,
    entity_type: str = "concept",
) -> str:
    """Store a new observation or fact in your personal memory.

    Use this to save important decisions, learnings, or context for later recall.

    Args:
        content: The fact or observation to remember
        entity_name: Optional entity this relates to (e.g. project name, technology)
        entity_type: Entity type (project/tool/concept/person/technology)
    """
    try:
        res = await _remote.store_observation(content, entity_name, entity_type)
    except Exception as e:
        return f"Store failed: {e}"
    return (
        f"Stored observation on entity **{res.get('entity_name', entity_name or 'Note')}** "
        f"({res.get('entity_id', '')[:8]}…)"
    )


@mcp.tool()
async def daily_summary(date_str: str | None = None) -> str:
    """Get daily activity summary for a specific date.

    Args:
        date_str: Date in YYYY-MM-DD format (default: today)
    """
    target = date_str or date.today().isoformat()

    try:
        data = await _remote.get_daily(target)
        total = data.get("total_messages", 0)
        if total == 0:
            return f"No activity recorded on {target}."

        tool_stats = data.get("overview", {}).get("tool_stats", {})
        conversations = data.get("overview", {}).get("conversations", [])
        summaries = data.get("summaries", [])

        parts = [f"# Activity Summary — {target}", f"\n**Total messages**: {total}\n"]

        # Tool breakdown
        parts.append("## Tools")
        for tool, count in sorted(tool_stats.items(), key=lambda x: -x[1]):
            parts.append(f"- **{tool}**: {count} messages")

        # Top conversations (real titles, not just counts)
        if conversations:
            parts.append("\n## Top Conversations")
            for c in conversations[:10]:
                title = c.get("title") or c.get("id", "")[:8]
                u = c.get("user_messages", 0)
                a = c.get("assistant_messages", 0)
                parts.append(f"- [{c.get('tool_id', '')}] **{title}** ({u}↑ {a}↓)")

        # AI summary if exists
        if summaries:
            for s in summaries:
                parts.append(f"\n## {s.get('title', 'AI Summary')}\n{s.get('summary', '')}")
        else:
            parts.append("\n*No AI summary yet. Generate one at https://mem.ihasy.com/daily/" + target + "*")

        return "\n".join(parts)
    except Exception as e:
        return f"Could not load daily summary for {target}: {e}"


# ---------------------------------------------------------------------------
# Drill-in tools: open / read / explore the graph
# ---------------------------------------------------------------------------

@mcp.tool()
async def memory_open(doc_id: str) -> str:
    """Fetch the full content of a document by its ID.

    Pair this with `memory_search` / `memory_recall` — those return short
    snippets, this returns the whole file so you can actually *read* the
    match instead of guessing from a fragment.

    Args:
        doc_id: Document UUID (from a search result's "id" field)
    """
    try:
        doc = await _remote.get_document(doc_id)
    except Exception as e:
        return f"Failed to fetch document: {e}"
    header = (
        f"# {doc.get('title') or doc.get('relative_path', 'Untitled')}\n"
        f"**Tool**: {doc.get('tool_id', '')}  ·  "
        f"**Category**: {doc.get('category', '')}  ·  "
        f"**Synced**: {(doc.get('synced_at') or '')[:10]}\n"
        f"**Path**: `{doc.get('relative_path', '')}`\n"
    )
    content = doc.get("content") or "(empty)"
    if doc.get("ai_summary"):
        header += f"\n**AI summary**: {doc['ai_summary']}\n"
    return f"{header}\n---\n{content}"


@mcp.tool()
async def memory_conversation(
    doc_id: str, limit: int = 50, offset: int = 0,
) -> str:
    """Read the actual message-by-message contents of a conversation document.

    Search results point you at a conversation; this tool unfolds the
    role/content turns so you can quote, summarize, or pick up where
    the past discussion left off.

    Args:
        doc_id: Conversation document UUID
        limit: Max messages to return (default 50, server caps at 200)
        offset: Pagination offset (default 0; use total + offset to page)
    """
    try:
        data = await _remote.get_conversation_messages(doc_id, limit=limit, offset=offset)
    except Exception as e:
        return f"Failed to fetch conversation: {e}"
    msgs = data.get("messages", [])
    total = data.get("total", len(msgs))
    if not msgs:
        return f"No messages in document {doc_id}."
    parts = [f"# Conversation {doc_id}\n*Messages {offset + 1}-{offset + len(msgs)} of {total}*\n"]
    for m in msgs:
        role = m.get("role") or "?"
        ts = (m.get("timestamp") or "")[:19].replace("T", " ")
        tool_name = m.get("tool_name")
        head = f"## {role}" + (f" ({ts})" if ts else "")
        if tool_name:
            head += f" — tool: `{tool_name}`"
        parts.append(head)
        if m.get("thinking"):
            parts.append(f"> _thinking_: {m['thinking']}")
        parts.append(m.get("content") or "(no text)")
    return "\n\n".join(parts)


@mcp.tool()
async def memory_graph(entity_name: str, limit: int = 5) -> str:
    """Explore the knowledge graph around an entity by name.

    Returns the matched entity (or top candidates if ambiguous), its
    summary, recent observations, and incoming/outgoing relations to
    other entities. Use this after `memory_search` when the AI needs
    structured "what do I know about X" instead of free-text snippets.

    Args:
        entity_name: Entity name to look up (fuzzy ilike match)
        limit: Max candidate entities to consider when the name is ambiguous
    """
    try:
        hits = await _remote.graph_search(entity_name, limit=limit)
    except Exception as e:
        return f"Graph search failed: {e}"
    # API returns mixed entities + observations; entities first.
    entities = [h for h in hits if h.get("type") == "entity"]
    if not entities:
        # No direct entity hit — show any matched observations as a
        # weak fallback so the AI still gets something to chew on.
        obs = [h for h in hits if h.get("type") == "observation"]
        if not obs:
            return f"No entity matching '{entity_name}'."
        lines = [f"# Observations mentioning '{entity_name}'\n"]
        for o in obs[:limit]:
            lines.append(f"- **{o.get('name', '')}**: {o.get('content', '')}")
        return "\n".join(lines)

    # Fetch full detail for the best (first) match.
    primary = entities[0]
    try:
        detail = await _remote.get_entity(primary["id"])
    except Exception as e:
        return f"Found entity '{primary.get('name')}' but detail fetch failed: {e}"

    parts = [
        f"# {detail.get('name', primary['name'])} "
        f"({detail.get('type') or detail.get('entity_type', '')})"
    ]
    if detail.get("summary"):
        parts.append(f"\n{detail['summary']}")

    outgoing = detail.get("outgoing_relations") or detail.get("outgoing") or []
    incoming = detail.get("incoming_relations") or detail.get("incoming") or []
    if outgoing:
        parts.append("\n## Relations (outgoing)")
        for r in outgoing[:20]:
            parts.append(
                f"- {r.get('relation', '')} → **{r.get('target_name', '')}** "
                f"({r.get('target_type', '')})"
            )
    if incoming:
        parts.append("\n## Relations (incoming)")
        for r in incoming[:20]:
            parts.append(
                f"- **{r.get('source_name', '')}** "
                f"({r.get('source_type', '')}) → {r.get('relation', '')} → here"
            )

    observations = detail.get("observations") or []
    if observations:
        parts.append("\n## Observations")
        for o in observations[:20]:
            date_str = (o.get("observed_at") or "")[:10]
            prefix = f"[{date_str}] " if date_str else ""
            parts.append(f"- {prefix}{o.get('content', '')}")

    if len(entities) > 1:
        parts.append("\n## Other candidates")
        for e in entities[1:limit]:
            parts.append(f"- {e.get('name', '')} ({e.get('entity_type', '')})")
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

@mcp.resource("memory://projects")
async def list_projects() -> str:
    """List all projects with document counts."""
    projects = await _remote.list_projects()
    if not projects:
        return "No projects found."
    lines = ["# Projects\n"]
    for p in projects[:50]:
        lines.append(f"- **{p.get('title', '')}** ({p.get('tool_id', '')}) — {p.get('document_count', 0)} files")
    return "\n".join(lines)


@mcp.resource("memory://projects/{name}")
async def get_project(name: str) -> str:
    """Get project details."""
    return await memory_context(name)


@mcp.resource("memory://identity/{tool}")
async def get_identity(tool: str) -> str:
    """Get tool identity files (AGENTS.md, SOUL.md, etc.)."""
    files = await _remote.get_tool_files(tool, category="identity")
    if not files:
        return f"No identity files found for {tool}."
    parts = []
    for f in files:
        doc = await _remote.get_document(f["id"])
        parts.append(f"## {doc.get('title', '')}\n\n{doc.get('content', '(empty)')}")
    return "\n\n---\n\n".join(parts)


@mcp.resource("memory://daily/{date_str}")
async def get_daily(date_str: str) -> str:
    """Get daily report for a specific date."""
    return await daily_summary(date_str)


@mcp.tool()
async def memory_core(category: str | None = None) -> str:
    """Get the user's permanent core memory (MEMORY.md) consolidated by dreaming.

    Contains distilled engineering rules, architecture decisions, project knowledge,
    and personal preferences. This is the L3 long-term curated tier.

    Args:
        category: Optional filter ('rule', 'architecture', 'preference', 'project', 'general')
    """
    if not category:
        data = await _remote.get_core_memory_markdown()
        return data.get("markdown", "")
    memories = [m for m in await _remote.get_core_memories(category=category) if not m.get("is_folder")]
    if not memories:
        return f"No core memories found for category '{category}'."
    lines = [f"# Core Memories ({category})"]
    for m in memories:
        lines.append(f"- **[{m.get('key')}]** ({m.get('confidence', 1.0)}): {m.get('content')}")
    return "\n".join(lines)


@mcp.resource("memory://core")
async def get_core_memory_resource() -> str:
    """Get the user's consolidated MEMORY.md."""
    return await memory_core()


@mcp.tool()
async def memory_check_rule(action_type: str, project_name: str | None = None, details: str | None = None) -> str:
    """Pre-flight check against the user's rules, past pitfalls, and learned skills.

    Call this BEFORE critical operations (release, deploy, build, db migration, deleting or
    changing data, git push, config change, restarting services). Returns the user's iron rules,
    pitfalls hit before on similar work (symptom / cause / fix), and skills to follow step by step.

    Args:
        action_type: What you are about to do (e.g. 'release', 'deploy', 'db_migration', '删除数据')
        project_name: Target project name, to include that project's pitfalls
        details: Optional specifics (commands, services, error text) to match more pitfalls
    """
    try:
        return await _remote.check(action_type, project_name, details)
    except Exception as e:
        return f"Rule check failed: {e}"


@mcp.tool()
async def memory_project_map() -> str:
    """Get a global portfolio map of all projects tracked in Memento.

    Returns the list of active engineering projects, their slug, title, primary tool,
    and document statistics. Use this to establish a high-level architectural overview
    of the user's workspace before drilling into specific projects.
    """
    projects = await _remote.list_projects()
    if not projects:
        return "No projects currently tracked in Memento."
    lines = [f"# Memento Workspace Project Map ({len(projects)} projects)\n"]
    for p in projects:
        title = p.get("title") or p.get("slug")
        slug = p.get("slug", "")
        tool = p.get("tool_id") or "universal"
        doc_count = p.get("document_count") or p.get("doc_count") or 0
        summary = p.get("summary") or ""
        desc = f": {summary}" if summary else ""
        lines.append(f"- **{title}** (`{slug}`) [{tool}] - {doc_count} docs{desc}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Learning loop: pitfalls, skills, todos
# ---------------------------------------------------------------------------

@mcp.tool()
async def memory_pitfall(
    title: str, symptom: str, fix: str, cause: str | None = None, project: str | None = None,
) -> str:
    """Record a pitfall after you hit a failure, found its cause, and fixed it.

    Memento will warn about it the next time similar work comes up (memory_check_rule).
    Only for problems in the user's project / machines / services — not for your own
    tool-usage mistakes, and not for failures whose cause you didn't find.

    Args:
        title: One line summary
        symptom: The error or behaviour you saw (keep the key error text)
        fix: What fixed it
        cause: The root cause
        project: Project name
    """
    try:
        res = await _remote.add_pitfall(title=title, symptom=symptom, fix=fix, cause=cause, project=project)
    except Exception as e:
        return f"Save failed: {e}"
    return "Saved." if res.get("saved") else f"Not saved: {res.get('note', '')}"


@mcp.tool()
async def memory_skill(query: str | None = None) -> str:
    """Skills the user approved: procedures that worked in their own environment.

    With a query (e.g. 'deploy memento', 'switch model'), returns the best matching skill's
    full steps; without one, lists all skills. Prefer following a skill over working it out again.

    Args:
        query: What you want to do, or a skill name
    """
    data = await _remote.list_skills()
    skills = data.get("published") or []
    if not skills:
        return "No published skills yet."
    if not query:
        return "\n".join(f"- `{s['slug']}` {s['title']}: {s['description']}" for s in skills)
    q = query.lower()
    words = [w for w in q.replace("-", " ").split() if len(w) > 1] or [q]

    def score(s: dict) -> int:
        text = f"{s['slug']} {s['title']} {s['description']} {s.get('project') or ''}".lower()
        return (10 if s["slug"] == q else 0) + sum(1 for w in words if w in text)

    best = max(skills, key=score)
    if score(best) == 0:
        return "No matching skill. Available:\n" + "\n".join(f"- `{s['slug']}` {s['title']}" for s in skills)
    return best.get("skill_md") or best.get("body") or ""


def _todo_line(t: dict) -> str:
    extra = []
    if t.get("due"):
        extra.append(f"due {t['due']}")
    if t.get("project"):
        extra.append(t["project"])
    return f"- [{t['id'][:8]}] {t['title']}" + (f" ({', '.join(extra)})" if extra else "")


@mcp.tool()
async def todo_list(project: str | None = None) -> str:
    """The user's open todos (things they said they'd do later), soonest due first.

    Args:
        project: Only this project's todos
    """
    data = await _remote.list_todos(project)
    items = data.get("open") or []
    if not items:
        return "No open todos."
    return f"# Open todos ({len(items)})\n" + "\n".join(_todo_line(t) for t in items)


@mcp.tool()
async def todo_add(title: str, detail: str | None = None, due: str | None = None, project: str | None = None) -> str:
    """Record something the user wants done later ("do this tomorrow", "note this down").

    Not for work you are about to do right now. The user gets a push when it falls due.

    Args:
        title: What to do, as a short verb phrase
        detail: Extra context
        due: Due date YYYY-MM-DD
        project: Project name
    """
    res = await _remote.add_todo(title, detail, due, project)
    t = res.get("todo") or {}
    return ("Added: " if res.get("created") else "Already on the list: ") + _todo_line(t)


@mcp.tool()
async def todo_update(
    todo_id: str, status: str | None = None, title: str | None = None, due: str | None = None,
) -> str:
    """Close or edit a todo. status: done | dropped | open. todo_id: the id (or its first 8 chars) from todo_list.

    Args:
        todo_id: Todo id or its 8-char prefix
        status: done, dropped, or open
        title: New title
        due: New due date YYYY-MM-DD ('' clears it)
    """
    full_id = todo_id
    if len(todo_id) < 32:
        data = await _remote.list_todos()
        match = [t for t in (data.get("open") or []) + (data.get("closed") or []) if t["id"].startswith(todo_id)]
        if len(match) != 1:
            return f"No single todo matches '{todo_id}'."
        full_id = match[0]["id"]
    fields = {k: v for k, v in {"status": status, "title": title, "due": due}.items() if v is not None}
    res = await _remote.update_todo(full_id, fields)
    return "Updated: " + _todo_line(res.get("todo") or {}) + f" [{(res.get('todo') or {}).get('status')}]"
