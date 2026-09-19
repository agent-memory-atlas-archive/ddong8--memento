"""Agent capabilities detection module.

Inspects local system to discover live models, default configurations,
and reasoning effort settings for Codex, Claude Code, and Antigravity.
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any

logger = logging.getLogger(__name__)


def get_codex_capabilities() -> dict[str, Any]:
    cache_file = os.path.expanduser("~/.codex/models_cache.json")
    config_file = os.path.expanduser("~/.codex/config.toml")

    default_model = ""
    default_effort = "medium"

    if os.path.isfile(config_file):
        try:
            with open(config_file, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("model ="):
                        default_model = line.split("=", 1)[1].strip().strip("\"'")
                    elif line.startswith("model_reasoning_effort ="):
                        default_effort = line.split("=", 1)[1].strip().strip("\"'")
        except Exception as e:
            logger.debug("Failed to read codex config.toml: %s", e)

    models: list[dict[str, Any]] = [
        {
            "id": "",
            "name": f"⚡ 默认模型 (跟随CLI配置: {default_model})" if default_model else "⚡ 默认模型 (跟随客户端配置)",
            "desc": f"当前配置: {default_model}" if default_model else "使用本地默认配置模型",
            "is_default": True,
        }
    ]

    found_slugs = set()
    if os.path.isfile(cache_file):
        try:
            with open(cache_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                raw_models = data.get("models", [])
                raw_models.sort(key=lambda m: (m.get("priority") or 999))
                for m in raw_models:
                    slug = m.get("slug")
                    if not slug or slug == "codex-auto-review":
                        continue
                    if slug in found_slugs:
                        continue
                    found_slugs.add(slug)
                    name = m.get("display_name") or slug
                    desc = m.get("description") or ""
                    is_active = (slug == default_model)
                    models.append({
                        "id": slug,
                        "name": f"{name} (当前主力)" if is_active else name,
                        "desc": desc,
                    })
        except Exception as e:
            logger.warning("Failed to parse codex models_cache.json: %s", e)

    # Fallback if cache file was empty or missing
    if len(models) == 1:
        fallback_models = [
            {"id": "gpt-6-astra", "name": "GPT-6-Astra (最新旗舰)", "desc": "前沿深度多步推理模型，复杂编码首选"},
            {"id": "gpt-reserve", "name": "GPT-Reserve (极速主力)", "desc": "高性价比快速编码与日常任务"},
            {"id": "gpt-5.6-sol", "name": "GPT-5.6-Sol (日常主力)", "desc": "可靠的主力 Agent 编码模型"},
            {"id": "gpt-5.6-terra", "name": "GPT-5.6-Terra", "desc": "均衡的高性价比日常模型"},
            {"id": "gpt-5.6-luna", "name": "GPT-5.6-Luna", "desc": "极速响应日常编码模型"},
            {"id": "gpt-5.5", "name": "GPT-5.5 (经典稳定)", "desc": "经典全能编码与推理模型"},
            {"id": "o3", "name": "o3 (深度思维)", "desc": "OpenAI 深度思维链"},
            {"id": "o4-mini", "name": "o4-mini", "desc": "轻量高速响应"},
        ]
        models.extend(fallback_models)

    effort_options = [
        {
            "id": "",
            "name": f"⚡ 默认 Effort ({default_effort})",
            "desc": f"使用本地配置的 reasoning_effort ({default_effort})",
        },
        {
            "id": "low",
            "name": "Low (快速 / 低思考量)",
            "desc": "轻量思考，极速响应，节省 Token",
        },
        {
            "id": "medium",
            "name": "Medium (标准思考量)",
            "desc": "平衡速度与推理质量，适合日常编程",
        },
        {
            "id": "high",
            "name": "High (深度推理 / 高思考量)",
            "desc": "深入思维链，攻坚复杂架构与疑难排错",
        },
    ]

    return {
        "tool": "codex",
        "models": models,
        "default_model": default_model,
        "supports_effort": True,
        "default_effort": default_effort,
        "effort_options": effort_options,
    }


def _format_claude_display_name(model_id: str) -> tuple[str, str]:
    m = model_id.lower()
    if "sonnet-4-5" in m:
        return "Claude Sonnet 4.5", "前沿多步推理与编码模型"
    if "sonnet-4" in m:
        return "Claude Sonnet 4", "前沿高智能推理模型"
    if "opus-4-1" in m:
        return "Claude Opus 4.1", "顶级复杂推理与工程攻坚"
    if "opus-4" in m:
        return "Claude Opus 4", "高阶架构设计与深度思维"
    if "3-7-sonnet" in m:
        return "Claude 3.7 Sonnet", "经典混合推理与编码模型 (当前主力)"
    if "3-5-sonnet" in m:
        return "Claude 3.5 Sonnet", "经典高性价比编码模型"
    if "haiku-4-5" in m:
        return "Claude Haiku 4.5", "毫秒级响应极速轻量模型"
    if "3-5-haiku" in m:
        return "Claude 3.5 Haiku", "极速轻量日常模型"
    if "opus" in m:
        return "Claude Opus", "高阶推理模型"
    parts = model_id.replace("claude-", "").split("-")
    name = "Claude " + " ".join(p.capitalize() for p in parts)
    return name, "官方支持模型"


def get_claude_capabilities() -> dict[str, Any]:
    import shutil
    import re

    claude_settings_file = os.path.expanduser("~/.claude/settings.json")
    default_model = ""
    default_effort = ""

    if os.path.isfile(claude_settings_file):
        try:
            with open(claude_settings_file, "r", encoding="utf-8") as f:
                cdata = json.load(f)
                default_model = str(cdata.get("model") or "").strip()
                default_effort = str(cdata.get("effortLevel") or "").strip()
        except Exception as e:
            logger.debug("Failed to read claude settings.json: %s", e)

    models: list[dict[str, Any]] = [
        {
            "id": "",
            "name": f"⚡ 默认模型 (跟随客户端配置: {default_model})" if default_model else "⚡ 默认模型 (跟随客户端/CLI配置)",
            "desc": f"当前本地配置: {default_model}" if default_model else "使用本地 Claude Code 配置的默认模型",
            "is_default": True,
        },
        {
            "id": "sonnet",
            "name": "sonnet (官方动态最新 Sonnet 别名)",
            "desc": "官方推荐别名，自动指向最新版本 (Claude 3.7 Sonnet / Sonnet 4.5)",
        },
        {
            "id": "opus",
            "name": "opus (官方动态最新 Opus 别名)",
            "desc": "官方推荐别名，极高智能与超长上下文 (Claude Opus 4.1 / Opus 4)",
        },
        {
            "id": "haiku",
            "name": "haiku (官方动态最新 Haiku 别名)",
            "desc": "官方推荐别名，极速轻量 (Claude Haiku 4.5 / 3.5 Haiku)",
        },
    ]

    seen_ids = {"", "sonnet", "opus", "haiku"}

    # Include user custom configured model if special (e.g. opus[1m])
    if default_model and default_model not in seen_ids:
        models.append({
            "id": default_model,
            "name": f"{default_model} (当前本地配置)",
            "desc": "本地 ~/.claude/settings.json 中配置的模型",
        })
        seen_ids.add(default_model)

    # Dynamically scan models supported by locally installed Claude Code runtime
    discovered_slugs = []
    claude_bin = shutil.which("claude")
    if claude_bin and os.path.isfile(claude_bin):
        try:
            with open(claude_bin, "r", errors="ignore") as f:
                content = f.read(8000000)
            matches = re.findall(r'firstParty:\"(claude-[^\"]+)\"', content)
            discovered_slugs = list(dict.fromkeys(matches))
        except Exception as e:
            logger.debug("Failed to scan claude binary: %s", e)

    if not discovered_slugs:
        discovered_slugs = [
            "claude-3-7-sonnet-20250219",
            "claude-sonnet-4-5-20250929",
            "claude-opus-4-1-20250805",
            "claude-sonnet-4-20250514",
            "claude-opus-4-20250514",
            "claude-3-5-sonnet-20241022",
            "claude-haiku-4-5-20251001",
            "claude-3-5-haiku-20241022",
        ]

    for slug in discovered_slugs:
        if slug in seen_ids:
            continue
        seen_ids.add(slug)
        dname, desc = _format_claude_display_name(slug)
        models.append({
            "id": slug,
            "name": f"{slug} ({dname})",
            "desc": desc,
        })

    effort_options = [
        {
            "id": "",
            "name": f"⚡ 默认 Effort (跟随配置: {default_effort})" if default_effort else "⚡ 默认 Effort (跟随CLI配置)",
            "desc": f"使用本地配置的 effortLevel ({default_effort})" if default_effort else "使用客户端配置的思考量",
        },
        {"id": "low", "name": "Low (快速 / 低思考量)", "desc": "轻量思考，极速响应，节省 Token"},
        {"id": "medium", "name": "Medium (标准思考量)", "desc": "平衡速度与推理质量，适合日常编程"},
        {"id": "high", "name": "High (深度推理 / 高思考量)", "desc": "深入思维链，攻坚复杂架构与排错"},
        {"id": "max", "name": "Max (最大思考量)", "desc": "顶级复杂任务深度多步探索"},
    ]

    return {
        "tool": "claude",
        "models": models,
        "default_model": default_model,
        "supports_effort": True,
        "default_effort": default_effort or "max",
        "effort_options": effort_options,
    }


def get_antigravity_capabilities() -> dict[str, Any]:
    models = [
        {
            "id": "",
            "name": "⚡ 默认模型 (系统配置: Gemini 3.8 Flash)",
            "desc": "使用当前 Antigravity 默认模型配置",
            "is_default": True,
        },
        {
            "id": "gemini-3.8-flash",
            "name": "Gemini 3.8 Flash (High, Fast)",
            "desc": "最新高智能极速响应模型 (Antigravity 默认主力推荐)",
        },
        {
            "id": "gemini-3.7-flash",
            "name": "Gemini 3.7 Flash (Medium, Fast)",
            "desc": "极速日常编码与高吞吐分析",
        },
        {
            "id": "gemini-3.6-flash",
            "name": "Gemini 3.6 Flash (Fast)",
            "desc": "轻量超低延迟模型",
        },
        {
            "id": "gemini-3.1-pro",
            "name": "Gemini 3.1 Pro (深度推理)",
            "desc": "高复杂度架构攻坚与深度逻辑推演",
        },
        {
            "id": "claude-sonnet-4-6",
            "name": "Claude Sonnet 4.6 (Thinking)",
            "desc": "原生嵌入 Antigravity 的高阶思维模型",
        },
        {
            "id": "claude-opus-4-6",
            "name": "Claude Opus 4.6 (Thinking)",
            "desc": "顶级架构分析与复杂逻辑推演",
        },
        {
            "id": "gpt-oss-120b",
            "name": "GPT-OSS 120B (Medium)",
            "desc": "开源高性价比大模型",
        },
        {
            "id": "flash",
            "name": "Gemini Flash (快速推荐)",
            "desc": "标准 Flash 阶梯 (自动映射最新 Gemini 3.8 Flash)",
        },
        {
            "id": "pro",
            "name": "Gemini Pro (强力推理)",
            "desc": "标准 Pro 阶梯 (自动映射最新 Gemini 3.1 Pro / Claude)",
        },
        {
            "id": "flash_lite",
            "name": "Gemini Flash-Lite (超轻量)",
            "desc": "超轻量阶梯 (自动映射 Gemini 3.6 Flash)",
        },
    ]

    return {
        "tool": "antigravity",
        "models": models,
        "default_model": "gemini-3.8-flash",
        "supports_effort": False,
        "default_effort": "",
        "effort_options": [],
    }


def get_all_agent_capabilities() -> dict[str, dict[str, Any]]:
    return {
        "codex": get_codex_capabilities(),
        "claude": get_claude_capabilities(),
        "antigravity": get_antigravity_capabilities(),
    }
