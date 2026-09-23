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
    Machine, Project, User, UserMemory,
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


def _safe_json_loads(text: str) -> dict[str, Any]:
    """Robustly parse JSON output from LLM, stripping markdown, code blocks and trailing commas."""
    if not text:
        return {}
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.split("\n", 1)[-1]
        if cleaned.endswith("```"):
            cleaned = cleaned[:-3]
    cleaned = cleaned.strip()
    start = cleaned.find("{")
    end = cleaned.rfind("}") + 1
    if start >= 0 and end > start:
        snippet = cleaned[start:end]
        try:
            return json.loads(snippet)
        except Exception:
            # Fix common trailing commas before closing brackets or braces
            fixed = re.sub(r",\s*([\]}])", r"\1", snippet)
            try:
                return json.loads(fixed)
            except Exception:
                pass
    return {}


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
   - 分类 (category) 仅限：`project` (核心业务项目), `architecture` (架构决策与技术栈), `rule` (开发铁律/规范避坑), `tools` (工具链与AI助手生态), `preference` (个人偏好习惯)。
   - tree_path: 严谨规范的3级树状路径，格式为 /维度/子目录/标识，如 /project/<项目名>/<模块>, /architecture/backend/<技术>, /rules/pitfalls/<规约>, /tools/ai_assistants/<工具>, /preference/workflow/<偏好>。
   - key 请使用小写英文+下划线，简短精确（如 `windows_update_policy`, `ios_background_keepalive`, `dart_analyzer_clean`）。
   - confidence: 0.0 ~ 1.0 (仅当大于等于 0.75 时才会正式写入)。
3. **知识图谱关系 (Knowledge Graph Links)**：
   - 如果发现关键概念/技术之间的明确关联，可输出实体关联（如：{{"source": "Windows更新", "target": "PowerShell", "relation": "uses"}}）。

请严格输出合法的 JSON 格式（不要输出任何前后注释或 markdown 外部包裹）：
{{
  "light_sleep_notes": "浅睡阶段总结：清洗与概括了哪些主要会话与工具活动",
  "rem_reflections": "REM阶段反思：观察到的核心模式、思考过程、跨项目共性与经验教训",
  "deep_consolidations": "深睡阶段固化：最终决定沉淀为长期核心记忆的决策理由与遗忘剪枝考量",
  "promoted_memories": [
    {{
      "category": "project",
      "tree_path": "/project/favorite_chat/overview",
      "key": "proj_favorite_chat_overview",
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


# ---------------------------------------------------------------------------
# Canonical Project Clustering & Extraction
# ---------------------------------------------------------------------------
CANONICAL_PROJECT_MAP: dict[str, dict[str, str]] = {
    "favorite_chat": {
        "slug": "favorite_chat",
        "title": "favorite_chat (库存/询单管理系统)",
        "default_summary": "Vue3 + FastAPI 驱动的库存与询单管理系统，包含前后端分离架构与数据导入、中转模块。",
    },
    "quant_future": {
        "slug": "quant_future",
        "title": "quant_future (量化交易与多因子回测)",
        "default_summary": "量化期货交易与多因子回测系统，支持高频行情接入、实盘部署流与策略回测引擎。",
    },
    "openclaw": {
        "slug": "openclaw",
        "title": "openclaw (AI 自动化客户端与桌面沙箱)",
        "default_summary": "OpenClaw 跨平台客户端与基于 KasmVNC 的容器化桌面沙箱运行环境，提供浏览器自动化与代理工具。",
    },
    "rke2_k8s": {
        "slug": "rke2_k8s",
        "title": "rke2_k8s (高可用 Kubernetes 集群基建)",
        "default_summary": "基于 RKE2/K3s 的双集群基础设施运维，整合 NAS 存储、DaoCloud 加速、容灾备份与 GitOps 自动化流水线。",
    },
    "yicaigou": {
        "slug": "yicaigou",
        "title": "yicaigou (易采购 B2B 化学品电商平台)",
        "default_summary": "B2B 化学品采购撮合与电商平台，前端采用 Next.js 15+React 18+TypeScript，后端采用 FastAPI+SQLAlchemy+MySQL。",
    },
    "daily_report": {
        "slug": "daily_report",
        "title": "daily_report (多源 AI 对话与研发聚合系统)",
        "default_summary": "三层级 AI 对话聚合与开发者日报系统，包含跨平台 Collector、FastAPI 服务端与数据可视化前端。",
    },
    "memento": {
        "slug": "memento",
        "title": "memento (开发者认知记忆与全生命周期收集系统)",
        "default_summary": "开发者全生命周期数据收集系统与认知记忆大脑，包含跨设备常驻采集器、三层记忆做梦固化管道与多端管理界面。",
    },
    "vps_infra": {
        "slug": "vps_infra",
        "title": "vps_infra (多节点 VPS 基础架构与网络网关)",
        "default_summary": "多台海外与国内 VPS 节点拓扑运维、Hysteria 隧道代理及基于 acme.sh 与 Cloudflare 的自动化证书续期体系。",
    },
    "wechat_gateway": {
        "slug": "wechat_gateway",
        "title": "wechat_gateway (企业微信/微信消息中转网关)",
        "default_summary": "微信协议与消息中转网关服务，支持消息路由监听、事件通知与多应用联动分发。",
    },
    "ray_train": {
        "slug": "ray_train",
        "title": "ray_train (分布式大模型训练与推理服务)",
        "default_summary": "基于 Ray 的分布式大语言模型训练、微调与低延迟推理部署方案，支持动态资源伸缩与 K8s 集群调度。",
    },
    "chembook": {
        "slug": "chembook",
        "title": "chembook (化学品分子百科与化合物图谱)",
        "default_summary": "面向化学合成与化合物数据的知识库与图谱检索系统，集成 PubChem、SMILES 结构式解析与属性索引。",
    },
    "easywork_copilot": {
        "slug": "easywork_copilot",
        "title": "easywork_copilot (跨平台统一研发 Copilot 协同大脑)",
        "default_summary": "跨应用协同的统一 AI Copilot Agent，统一调度 IMS、易商城、易反应等多业务系统，实现一句话自然语言驱动操作。",
    },
    "bulk_import": {
        "slug": "bulk_import",
        "title": "bulk_import (批量数据解析与高并发流式导入)",
        "default_summary": "高性能大容量 Excel/CSV 批量数据异步解析、动态列映射与入库流水线服务。",
    },
    "alphacas_reaction": {
        "slug": "alphacas_reaction",
        "title": "alphacas_reaction (易反应逆合成与化学反应 RAG)",
        "default_summary": "化学逆合成路线预测与反应机理知识库，结合反应式爬虫与专业化学领域 RAG 检索问答系统。",
    },
    "aiphacas_eln": {
        "slug": "aiphacas_eln",
        "title": "aiphacas_eln (电子实验记录本系统 ELN)",
        "default_summary": "智能化实验室电子记录本与研发门户，规范实验方案记录、谱图附件关联与科研流程合规留痕。",
    },
    "sso": {
        "slug": "sso",
        "title": "sso (统一身份认证与单点登录鉴权中心)",
        "default_summary": "基于 JWT 与 OAuth2 的统一单点登录与权限认证中台，支持跨系统 Token 续期与统一用户画像。",
    },
    "aipay": {
        "slug": "aipay",
        "title": "aipay (多通道支付与账务结算中台)",
        "default_summary": "集成微信支付、支付宝及企业对公账户的统一支付中台，提供可靠异步对账与订单回调保障。",
    },
    "sglang": {
        "slug": "sglang",
        "title": "sglang (高性能 LLM 结构化推理与本地部署)",
        "default_summary": "基于 SGLang 运行时与 RadixAttention 的超高速大模型推理引擎部署与吞吐优化方案。",
    },
}


PROJECT_ALIAS_MAP: dict[str, str] = {
    # 易采购 & 商城
    "易采购": "yicaigou",
    "易采购(yicaigou)": "yicaigou",
    "易采购_b2b_化学品商城": "yicaigou",
    "易采购b2b化学品商城": "yicaigou",
    "易采购b2b商城": "yicaigou",
    "易采购后端": "yicaigou",
    "化学品商城": "yicaigou",
    "商城": "yicaigou",
    "collaborative_chemical_procurement_system": "yicaigou",

    # 易商城
    "易商城": "yishangcheng",
    "易商城_mall": "yishangcheng",
    "mall": "yishangcheng",

    # 易工作 / favorite_chat
    "易工作": "favorite_chat",
    "易工作平台": "favorite_chat",
    "favorite_chat_项目": "favorite_chat",

    # 协同与 Copilot
    "易工作_copilot": "easywork_copilot",
    "易工作_copilot_agent": "easywork_copilot",
    "copilot": "easywork_copilot",
    "copilot_后端": "easywork_copilot",
    "copilot_backend": "easywork_copilot",
    "external_copilot": "easywork_copilot",
    "外部_copilot_服务": "easywork_copilot",
    "tool_calling_ai_agent_服务": "easywork_copilot",

    # 易反应
    "易反应": "alphacas_reaction",
    "易反应(alphacas_reaction)": "alphacas_reaction",
    "易反应_反应搜索": "alphacas_reaction",
    "alphacas_reaction(易反应)": "alphacas_reaction",
    "alphacas_api": "alphacas_reaction",

    # 易合成平台
    "易合成": "aiphacas_platform",
    "易合成(aiphacas)平台": "aiphacas_platform",
    "易合成平台": "aiphacas_platform",
    "aiphacas平台": "aiphacas_platform",
    "aiphacas易合成平台": "aiphacas_platform",
    "aiphacas_综合管理后台": "aiphacas_platform",
    "aiphacas_portal": "aiphacas_platform",
    "aiphacas_price": "aiphacas_platform",
    "cas价格查询服务": "aiphacas_platform",
    "cas_price": "aiphacas_platform",

    # 逆合成
    "逆合成": "retrosynthesis",
    "逆合成(retrosynthesis)": "retrosynthesis",
    "逆合成应用": "retrosynthesis",
    "逆合成应用_retrosynthesis_api": "retrosynthesis",
    "retrosynthesis_应用": "retrosynthesis",
    "retrosynthesis(逆合成)": "retrosynthesis",
    "retrosynthesis_api": "retrosynthesis",
    "retrosynthesis_app": "retrosynthesis",

    # 易查询 / ChemBook
    "易查询(chembook)": "chembook",
    "易查询_chembook": "chembook",
    "chembook(易查询)": "chembook",
    "chemicalbook_crawler": "chembook_crawler",
    "chembook_frontend": "chembook",

    # 易翻译
    "易翻译": "alphacas_translate",
    "易翻译(alphacas_translate)": "alphacas_translate",

    # 易支付
    "易支付项目": "aipay",
    "统一支付网关": "aipay",

    # SSO
    "企业内部sso单点登录系统": "sso",
    "sso_login_项目": "sso_login",
    "sso_系统": "sso",
    "sso_系统前端": "sso",
    "sso_项目": "sso",
    "sso前端管理后台": "sso",
    "sso单一身份项目": "sso",
    "login_页面": "sso_login",
    "login_frontend": "sso_login",
    "login": "sso_login",
    "favorite_chat_login": "sso_login",

    # 量化 & 回测
    "量化交易程序": "quant_future",
    "quant_future_backend": "quant_future",
    "quant_future_前端项目": "quant_future",
    "quant_backtest_service": "quant_backtest",
    "backtest": "quant_backtest",
    "backtestengine": "quant_backtest",
    "qbacktest": "quant_backtest",
    "trading_qbacktest": "quant_backtest",
    "trading_backend": "trading_platform",

    # 云原生 K8s
    "rke2_cicd_pilot": "rke2_k8s",
    "rke2_k8s_cicd_pilot": "rke2_k8s",
    "rke2_k8s_集群": "rke2_k8s",
    "aliyun_k3s_cluster": "rke2_k8s",
    "k3s_github": "rke2_k8s",
    "nas_k3s": "rke2_k8s",
    "k3s_synology": "rke2_k8s",
    "nas集群": "nas_infra",
    "nas": "nas_infra",

    # 日报
    "daily_report_collector": "daily_report",
    "daily_report_web": "daily_report",
    "ai_daily_report": "daily_report",
    "ai_daily_report_project": "daily_report",

    # Memento
    "memento_server": "memento",
    "memento_api": "memento",
    "collector_cli": "memento_collector",
    "collector": "memento_collector",
    "ai_工具内存文件收集系统": "memento_collector",

    # 语音与 AI 基础设施
    "funasr_server": "funasr",
    "funasr_wss_server": "funasr",
    "funasr_runtime_sdk": "funasr",
    "openai_whisper_asr_webservice": "whisperx",

    # OpenClaw
    "openclaw_gateway": "openclaw_gateway",
    "openclaw_main": "openclaw",
    "openclaw助手": "openclaw",
    "project_openclaw_desktop": "openclaw_desktop",

    # VPS
    "vps1": "vps_infra",
    "vps3": "vps_infra",
    "vps3_us": "vps_infra",
    "vps文档仓库": "vps_infra",
    "vps": "vps_infra",

    # WeChat
    "wechat_msg": "wechat_gateway",
    "wechat": "wechat_gateway",
    "webchat": "wechat_gateway",

    # ELN
    "eln": "aiphacas_eln",
    "eln(aiphacas_eln)": "aiphacas_eln",
    "alphacas_eln": "aiphacas_eln",
    "eln_api": "aiphacas_eln",
    "aiphacas_eln(eln)": "aiphacas_eln",
    "gitee_vavafan_aiphacas_eln": "aiphacas_eln",
    "gitlab_aiphacas_com_frank_aiphacas_eln": "aiphacas_eln",

    # Bulk Import
    "bulk_import_ims": "bulk_import",
    "bulk_import_ims_(ims.aiphacas.com)": "bulk_import",
    "bulk_import_backend": "bulk_import",
    "bulk_import_后端": "bulk_import",
    "bulk_import_项目": "bulk_import",
    "bulk_import(ims)": "bulk_import",
    "bulk_import/desktop": "bulk_import",
    "bulk_import后端": "bulk_import",
    "bulk_import项目": "bulk_import",
    "favorite_chat_bulk_import": "bulk_import",

    # IMS
    "ims_(bulk_import)": "ims",
    "ims_(询单系统)": "ims",
    "ims_bulk_import": "ims",
    "ims_inventory": "ims",
    "ims_对外接口": "ims",
    "ims_系统": "ims",
    "ims(bulk_import)": "ims",
    "ims搜索定位功能": "ims",
    "inquirylist": "ims_inquiry",

    "inventory_backend": "inventory",
    "inventory后端": "inventory",
    "order_backend": "order",
    "order后端": "order",
    "rd_backend": "rd",
    "rd后端": "rd",

    "后端_websocket_桥接": "backend_bridge",
    "后端桥接服务": "backend_bridge",
    "python_后端桥接": "backend_bridge",

    "mem0_dashboard": "mem0",
}

IGNORE_SLUGS: set[str] = {
    "oom_cpu治理任务", "基础设施侦察任务", "外接硬盘盒诊断", "influxdb_移除任务",
    "phase_b_2", "errors_log", "test_项目", "ver1_kbw_04_17", "0212", "abc215",
    "120_78_4_157", "内网穿透方案", "product_catalog_module", "pdf预览项目",
    "chrome扩展", "systemd_ubuntu", "docker_gpu_镜像", "demo", "workspace",
    "donghaixing", "antigravity_history", "antigravity_con",
}


def resolve_canonical_slug(raw_name: str) -> str:
    """Normalize raw project slug/title or directory name to a canonical project slug."""
    n = raw_name.lower().strip()
    for prefix in (
        "antigravity/", "claude_code/", "codex/", "cursor/", "ddong8/",
        "pskoett/", "fenio/", "jrei/", "linuxserver/", "onerahmet/",
        "gitee_vavafan/", "gitlab_aiphacas_com_frank/",
    ):
        if n.startswith(prefix):
            n = n[len(prefix):]
    n = re.sub(r"[\s\-/\.]+", "_", n).strip("_")
    n = re.sub(r"_\([^)]+\)$", "", n)
    mapped = PROJECT_ALIAS_MAP.get(n, PROJECT_ALIAS_MAP.get(raw_name.strip(), n))
    return mapped or "other"


async def extract_canonical_projects(db: AsyncSession, user: User) -> list[dict[str, Any]]:
    """Extract and aggregate all canonical projects from documents and knowledge graph for user."""
    user_machines_subq = select(Machine.id).where(Machine.user_id == user.id)
    doc_projects_res = await db.execute(
        select(Project.slug, Project.title, func.count(Document.id))
        .outerjoin(Document, Document.project_id == Project.id)
        .where(Document.machine_id.in_(user_machines_subq))
        .group_by(Project.id)
    )
    doc_projects = doc_projects_res.all()

    ke_projects_res = await db.execute(
        select(KnowledgeEntity.name, KnowledgeEntity.summary, func.count(KnowledgeObservation.id))
        .outerjoin(KnowledgeObservation, KnowledgeObservation.entity_id == KnowledgeEntity.id)
        .where(KnowledgeEntity.user_id == user.id, KnowledgeEntity.entity_type == "project")
        .group_by(KnowledgeEntity.id)
    )
    ke_projects = ke_projects_res.all()

    results: dict[str, dict[str, Any]] = {}

    for row in doc_projects:
        raw_name = str(row[0] or (row[1] if len(row) > 1 else "") or "").strip()
        if not raw_name:
            continue
        slug = resolve_canonical_slug(raw_name)
        if not slug or len(slug) < 2 or slug in IGNORE_SLUGS:
            continue
        count_val = row[2] if len(row) > 2 and isinstance(row[2], (int, float)) else 0
        if slug not in results:
            defn = CANONICAL_PROJECT_MAP.get(slug, {})
            title = defn.get("title") or (row[1] if len(row) > 1 and row[1] else slug)
            summary = defn.get("default_summary") or ""
            results[slug] = {
                "slug": slug,
                "title": title,
                "summary": summary,
                "doc_count": 0,
                "obs_count": 0,
            }
        results[slug]["doc_count"] += int(count_val)

    for row in ke_projects:
        raw_name = str(row[0] or "").strip()
        if not raw_name:
            continue
        slug = resolve_canonical_slug(raw_name)
        if not slug or len(slug) < 2 or slug in IGNORE_SLUGS:
            continue
        summary_val = str(row[1] or "") if len(row) > 1 and isinstance(row[1], str) else ""
        count_val = row[2] if len(row) > 2 and isinstance(row[2], (int, float)) else 0
        if slug not in results:
            defn = CANONICAL_PROJECT_MAP.get(slug, {})
            title = defn.get("title") or raw_name
            summary = summary_val or defn.get("default_summary") or ""
            results[slug] = {
                "slug": slug,
                "title": title,
                "summary": summary,
                "doc_count": 0,
                "obs_count": 0,
            }
        results[slug]["obs_count"] += int(count_val)
        if summary_val and len(summary_val.strip()) > len(results[slug]["summary"]):
            results[slug]["summary"] = summary_val.strip()

    # Fill default summary for projects without explicit description
    for p in results.values():
        if not p["summary"]:
            p["summary"] = f"活跃研发项目，包含跨设备同步与事实追踪（关联 {p['doc_count']} 份文档，{p['obs_count']} 条知识事实）。"

    # Retain all active projects with engineering footprint
    active_projs = [
        p for p in results.values()
        if (p["doc_count"] > 0 or p["obs_count"] > 0)
    ]

    # Return sorted by relevance (doc_count + obs_count desc)
    sorted_projs = sorted(
        active_projs,
        key=lambda x: (x["doc_count"] + x["obs_count"]),
        reverse=True,
    )
    return sorted_projs


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
    elif days_back <= 0:
        # Full-history panoramic dreaming (sweep all history from 2020 to today)
        since_date = date(2020, 1, 1)
        until_date = today
        since_dt = datetime(2020, 1, 1, tzinfo=timezone.utc)
        until_dt = now
    else:
        until_date = today
        since_date = today - timedelta(days=days_back)
        until_dt = now
        since_dt = now - timedelta(days=days_back)

    # -----------------------------------------------------------------------
    # Phase 1: Light Sleep (Ingest & Filter)
    # -----------------------------------------------------------------------
    # 0. Gather canonical projects panorama
    canonical_projects = await extract_canonical_projects(db, user)
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

    # 4. Gather Documents synced/created in this window (titles, categories & summaries)
    doc_limit = 100 if days_back <= 0 else 30
    doc_res = await db.execute(
        select(Document.title, Document.category, Document.ai_summary)
        .where(
            Document.machine_id.in_(user_machines_subq),
            Document.created_at >= since_dt,
            Document.created_at <= until_dt,
        )
        .order_by(Document.created_at.desc())
        .limit(doc_limit)
    )
    window_docs = doc_res.all()

    # 5. Gather Knowledge Entities updated/created in this window
    ent_limit = 50 if days_back <= 0 else 20
    ent_res = await db.execute(
        select(KnowledgeEntity.name, KnowledgeEntity.entity_type, KnowledgeEntity.summary)
        .where(
            KnowledgeEntity.user_id == user.id,
            KnowledgeEntity.updated_at >= since_dt,
            KnowledgeEntity.updated_at <= until_dt,
        )
        .order_by(KnowledgeEntity.updated_at.desc())
        .limit(ent_limit)
    )
    window_ents = ent_res.all()

    # Compile raw activity notes
    activity_snippets: list[str] = []
    scanned_count = (
        len(daily_summaries)
        + len(ask_convs)
        + len(recent_msgs)
        + len(window_docs)
        + len(window_ents)
        + len(canonical_projects)
    )

    if canonical_projects:
        proj_lines = [
            f"- {p['slug']} ({p['title']}): {p['summary']} (关联文档: {p['doc_count']}, 观察事实: {p['obs_count']})"
            for p in canonical_projects
        ]
        activity_snippets.append("### 【用户核心业务项目全景一览】\n" + "\n".join(proj_lines))

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

    if window_docs:
        activity_snippets.append("\n### 【开发会话与文档主题】")
        for d_title, d_cat, d_summary in window_docs:
            if not d_title and not d_summary:
                continue
            cat_tag = d_cat.strip() if d_cat else "session"
            title_text = (d_title or "未命名会话").strip()
            if d_summary:
                clean_sum = sanitize_transient_text(d_summary)[:180]
                activity_snippets.append(f"- [{cat_tag}] {title_text}: {clean_sum}")
            else:
                activity_snippets.append(f"- [{cat_tag}] {title_text}")

    if window_ents:
        activity_snippets.append("\n### 【提炼技术实体与知识图谱】")
        for e_name, e_type, e_summary in window_ents:
            type_tag = e_type.strip() if e_type else "concept"
            name_text = e_name.strip()
            if e_summary:
                clean_e_sum = e_summary.strip()[:150]
                activity_snippets.append(f"- [{type_tag}] {name_text}: {clean_e_sum}")
            else:
                activity_snippets.append(f"- [{type_tag}] {name_text}")

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
                llm_output = _safe_json_loads(raw_response)
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

    # Guarantee pass: For on-demand or full-history dreaming, guarantee that EVERY canonical project exists under /project/<slug>/...
    if days_back <= 0 or tag in ("on_demand", "bootstrap"):
        existing_mem_check = (await db.execute(
            select(UserMemory.tree_path, UserMemory.key).where(
                UserMemory.user_id == user.id,
                UserMemory.category == "project",
            )
        )).all()
        existing_paths = {row[0] for row in existing_mem_check if row[0]}
        existing_keys = {row[1] for row in existing_mem_check if row[1]}

        for p in canonical_projects:
            slug = p["slug"]
            expected_path = f"/project/{slug}/overview"
            expected_key = f"proj_{slug}_overview"
            already_covered = any(f"/project/{slug}" in path for path in existing_paths) or expected_key in existing_keys
            if not already_covered:
                content_desc = f"【{p['title']}】{p['summary']}"
                db.add(UserMemory(
                    user_id=user.id,
                    category="project",
                    key=expected_key,
                    content=content_desc,
                    confidence=0.92,
                    source="dreaming",
                    tree_path=expected_path,
                    created_at=now,
                    updated_at=now,
                ))
                existing_paths.add(expected_path)
                existing_keys.add(expected_key)
                promoted_count += 1
                promoted_details.append(f"- 🌟 新增【{expected_path}】: {content_desc}")

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

    # 4. Earliest KnowledgeEntity
    ent_min_q = select(func.min(KnowledgeEntity.created_at)).where(
        KnowledgeEntity.user_id == user.id
    )
    ent_min_dt = (await db.execute(ent_min_q)).scalar()
    ent_min = ent_min_dt.date() if ent_min_dt else None

    dates = [d for d in (daily_min, doc_min, ask_min, ent_min) if d is not None]
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

        # Check documents
        has_doc = (await db.execute(
            select(func.count()).select_from(Document).where(
                Document.machine_id.in_(user_machines_subq),
                Document.created_at >= w_start_dt,
                Document.created_at <= w_end_dt,
            )
        )).scalar() or 0

        # Check knowledge entities
        has_ent = (await db.execute(
            select(func.count()).select_from(KnowledgeEntity).where(
                KnowledgeEntity.user_id == user.id,
                KnowledgeEntity.updated_at >= w_start_dt,
                KnowledgeEntity.updated_at <= w_end_dt,
            )
        )).scalar() or 0

        if has_daily == 0 and has_ask == 0 and has_msg == 0 and has_doc == 0 and has_ent == 0:
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


# ---------------------------------------------------------------------------
# Cold-start Knowledge Bootstrapping Engine
# ---------------------------------------------------------------------------
_BOOTSTRAP_PROMPT = """你是一个高阶个人认知知识图谱与大脑记忆架构师。
请根据用户在数据库中的历史核心项目、技术实体与观察事实，从【五大维度】进行全量多维度归纳总结，输出一套具有明确层级树状路径（3级路径 /维度/子目录/标识）的核心记忆树。

五大维度划分：
1. /project/<项目slug>/<子模块>：核心业务项目（如 /project/quant_future/strategy, /project/yicaigou/overview 等）
2. /architecture/<领域>/<技术条目>：架构设计与技术选型（领域划分：backend, frontend, infra, client）
3. /rules/<领域>/<规范条目>：开发铁律、避坑指南与工程规范（领域划分：pitfalls, engineering, security）
4. /tools/<分类>/<工具名>：工具链与AI助手生态（分类划分：ai_assistants, dev_tools, asr）
5. /preference/<分类>/<偏好名>：个人偏好与开发习惯（分类划分：workflow, coding_style）

【重要铁律 - 必须全数收录每一个核心项目】：
以下列出的所有核心项目，在输出的 memories 列表中必须每一个都至少出现一条记录！
其 tree_path 必须为 /project/<项目slug>/...，如 /project/quant_future/strategy, /project/favorite_chat/overview, /project/openclaw/desktop 等。
严禁漏掉任何一个项目！

请输出严格合法的 JSON 格式（不要额外解释）：
{{
  "summary": "从五大维度全面梳理的认知记忆全景概览",
  "memories": [
    {{
      "category": "project | architecture | rule | tools | preference",
      "tree_path": "/维度/子目录/标识",
      "key": "unique_key",
      "title": "简短标题",
      "content": "高度凝练、具有长期指导意义的核心经验描述（60~150字）",
      "confidence": 0.95
    }}
  ]
}}

### 用户历史核心项目 (必须全部收录于 /project/<slug>/...)
{projects_text}

### 用户核心技术栈与工具
{tech_text}

### 知识图谱关键观察事实与开发经验
{observations_text}
"""


async def bootstrap_memories_from_knowledge_graph(
    db: AsyncSession,
    user: User,
    max_entities: int = 80,
) -> dict[str, Any]:
    """Bootstrap the initial L3 UserMemory tree directly from historical KnowledgeEntities and Observations.

    This provides instantaneous cold-start distillation for accounts that already contain thousands
    of documents and knowledge entities in the database.
    """
    now = datetime.now(timezone.utc)
    today = date.today()

    # 1. Gather all canonical projects (from documents + knowledge entities)
    canonical_projects = await extract_canonical_projects(db, user)
    projs_text = "\n".join([
        f"- {p['slug']} ({p['title']}): {p['summary']} (关联文档数: {p['doc_count']}, 观察事实数: {p['obs_count']})"
        for p in canonical_projects
    ]) or "(无显著项目记录)"

    # 2. Gather top technologies and tools
    tech_res = await db.execute(
        select(KnowledgeEntity.name, KnowledgeEntity.entity_type, KnowledgeEntity.summary, func.count(KnowledgeObservation.id))
        .outerjoin(KnowledgeObservation, KnowledgeObservation.entity_id == KnowledgeEntity.id)
        .where(KnowledgeEntity.user_id == user.id, KnowledgeEntity.entity_type.in_(["technology", "tool"]))
        .group_by(KnowledgeEntity.id)
        .order_by(func.count(KnowledgeObservation.id).desc())
        .limit(20)
    )
    techs = tech_res.all()
    tech_text = "\n".join([f"- [{t[1]}] {t[0]}: {t[2][:140]}" for t in techs if t[2]]) or "(无显著技术栈记录)"

    # 3. Gather rich observations
    obs_res = await db.execute(
        select(KnowledgeObservation.content)
        .join(KnowledgeEntity, KnowledgeEntity.id == KnowledgeObservation.entity_id)
        .where(KnowledgeEntity.user_id == user.id, func.length(KnowledgeObservation.content) >= 15)
        .order_by(KnowledgeObservation.observed_at.desc())
        .limit(40)
    )
    obs = [r[0] for r in obs_res.all()]
    obs_text = "\n".join([f"- {r[:180]}" for r in obs]) or "(无显著观察事实)"

    llm_output: dict[str, Any] = {}
    if get_ai_providers() and (canonical_projects or techs or obs):
        prompt = _BOOTSTRAP_PROMPT.format(
            projects_text=projs_text,
            tech_text=tech_text,
            observations_text=obs_text,
        )
        try:
            raw_response = await call_plain_chat(
                messages=[
                    {
                        "role": "system",
                        "content": "You are the Memento Multi-Dimensional Memory Kernel. Output valid JSON only.",
                    },
                    {"role": "user", "content": prompt},
                ],
                max_tokens=4096,
            )
            if raw_response:
                llm_output = _safe_json_loads(raw_response)
        except Exception as e:
            logger.warning("Bootstrap LLM call failed, falling back to heuristic: %s", e)

    # Fallback to heuristic multi-dimensional distillation if LLM output is empty
    memories_to_persist: list[dict[str, Any]] = []
    if llm_output and llm_output.get("memories"):
        summary_text = str(llm_output.get("summary") or "从五大维度全面梳理的认知记忆全景概览。")
        for item in llm_output["memories"]:
            cat = str(item.get("category", "general")).strip().lower()
            key = str(item.get("key", "note")).strip().lower().replace(" ", "_")
            content = str(item.get("content", "")).strip()
            confidence = float(item.get("confidence", 0.92))
            tree_path = str(item.get("tree_path") or f"/{cat}/{key}").strip()
            if content and confidence >= 0.70:
                memories_to_persist.append({
                    "category": cat,
                    "key": key,
                    "content": content,
                    "confidence": confidence,
                    "tree_path": tree_path,
                })
    else:
        summary_text = "启发式多维度规则自举：按项目、架构设计、开发规范、工具生态与个人习惯分层梳理记忆树。"
        for p in canonical_projects:
            slug = p["slug"]
            memories_to_persist.append({
                "category": "project",
                "key": f"proj_{slug}_overview",
                "content": f"【{p['title']}】{p['summary']}",
                "confidence": 0.92,
                "tree_path": f"/project/{slug}/overview",
            })
        for t in techs:
            clean_k = re.sub(r"[^a-zA-Z0-9_]+", "_", t[0].lower()).strip("_")
            if not clean_k or not t[2]:
                continue
            lower_name = t[0].lower()
            if lower_name in ("postgresql", "fastapi", "influxdb", "python", "ray", "celery", "parquet"):
                sub = "backend"
                cat = "architecture"
            elif lower_name in ("nextjs", "vue", "tailwind", "react", "sse"):
                sub = "frontend"
                cat = "architecture"
            elif lower_name in ("flutter", "tauri"):
                sub = "client"
                cat = "architecture"
            elif lower_name in ("claude_code", "openclaw", "codex", "antigravity", "windsurf"):
                sub = "ai_assistants"
                cat = "tools"
            elif "asr" in lower_name or "voice" in lower_name:
                sub = "asr"
                cat = "tools"
            elif t[1] == "tool":
                sub = "workflow"
                cat = "preference"
            else:
                sub = "infra"
                cat = "architecture"

            memories_to_persist.append({
                "category": cat,
                "key": clean_k,
                "content": t[2].strip(),
                "confidence": 0.88,
                "tree_path": f"/{cat}/{sub}/{clean_k}",
            })

    # Guarantee pass: Ensure EVERY canonical project has at least one memory under /project/<slug>/...
    existing_proj_slugs = set()
    for item in memories_to_persist:
        tp = item.get("tree_path", "")
        if tp.startswith("/project/"):
            parts = [p for p in tp.split("/") if p]
            if len(parts) >= 2:
                existing_proj_slugs.add(parts[1])

    for p in canonical_projects:
        slug = p["slug"]
        if slug not in existing_proj_slugs:
            memories_to_persist.append({
                "category": "project",
                "key": f"proj_{slug}_overview",
                "content": f"【{p['title']}】{p['summary']}",
                "confidence": 0.92,
                "tree_path": f"/project/{slug}/overview",
            })
            existing_proj_slugs.add(slug)

    # Persist into UserMemory
    promoted_count = 0
    promoted_details: list[str] = []
    for item in memories_to_persist:
        cat = item["category"]
        key = item["key"]
        content = item["content"]
        confidence = item["confidence"]
        tree_path = item["tree_path"]

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
            existing.source = "bootstrap"
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
                source="bootstrap",
                tree_path=tree_path,
                created_at=now,
                updated_at=now,
            ))
            promoted_details.append(f"- 🌟 新增【{tree_path}】: {content}")
        promoted_count += 1


    # Record DreamJournal entry for bootstrap
    journal_report = f"""# 🌌 全量知识图谱冷启动自举报告 (Knowledge Bootstrap)

**自举时间**: {now.strftime('%Y-%m-%d %H:%M:%S UTC')}
**模式**: 全量历史知识图谱与开发会话自举沉淀
**晋升记忆数量**: {promoted_count} 条核心节点

---

## 📋 自举总结
{summary_text}

## 🌟 沉淀的长期核心记忆
""" + "\n".join(promoted_details)

    journal = DreamJournal(
        user_id=user.id,
        dream_date=today,
        stage_metrics={
            "tag": "bootstrap",
            "projects_scanned": len(canonical_projects),
            "tech_scanned": len(techs),
            "observations_scanned": len(obs),
            "promoted_count": promoted_count,
        },
        light_sleep_notes=f"扫描历史库中 {len(canonical_projects)} 个核心项目、{len(techs)} 个技术工具实体及 {len(obs)} 条深度观察事实。",
        rem_reflections=summary_text,
        deep_consolidations=f"完成全局认知记忆自举，确立 {promoted_count} 条高置信度长时核心记忆。",
        report_markdown=journal_report,
        created_at=now,
    )
    db.add(journal)
    await db.commit()

    return {
        "status": "success",
        "summary": summary_text,
        "promoted_count": promoted_count,
        "journal_id": str(journal.id),
        "memories": memories_to_persist,
    }

