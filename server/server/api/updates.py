"""Client auto-update distribution API.

Serves update metadata and client packages directly from the Memento server,
enabling intranet/self-hosted automatic client upgrades without external GitHub dependencies,
while dynamically synchronizing with GitHub Releases when available.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import time
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse, RedirectResponse
from pydantic import BaseModel

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/system/update", tags=["system-update"])

# Storage candidates for update packages
_CANDIDATES = [
    Path(os.environ.get("MEMENTO_UPDATES_DIR", "")) if os.environ.get("MEMENTO_UPDATES_DIR") else None,
    Path("/app/data/updates"),
    Path(__file__).resolve().parents[3] / "data" / "updates",
]
_UPDATES_DIR = next((p for p in _CANDIDATES if p and p.exists()), _CANDIDATES[-1])

# GitHub release configuration
GITHUB_REPO = os.environ.get("MEMENTO_GITHUB_REPO", "ddong8/memento")
GITHUB_CACHE_TTL = int(os.environ.get("MEMENTO_UPDATE_CACHE_TTL", "300"))  # 5 minutes

# In-memory cache for latest GitHub release metadata: (cached_at_timestamp, release_dict)
_RELEASE_CACHE: dict[str, Any] = {"time": 0.0, "data": None}


class UpdateCheckResponse(BaseModel):
    has_update: bool
    latest_version: str = ""
    current_version: str = ""
    title: str = ""
    release_notes: str = ""
    published_at: str | None = None
    download_url: str | None = None
    upstream_url: str | None = None
    asset_name: str | None = None
    asset_size: int | None = None
    sha256: str | None = None


def _compare_semver(target: str, current: str) -> bool:
    """Return True if target > current."""
    if not target or not current:
        return False
    t_nums = [int(n) for n in re.findall(r"\d+", target)] or [0]
    c_nums = [int(n) for n in re.findall(r"\d+", current)] or [0]
    max_len = max(len(t_nums), len(c_nums))
    t_nums.extend([0] * (max_len - len(t_nums)))
    c_nums.extend([0] * (max_len - len(c_nums)))
    return t_nums > c_nums


def _find_platform_asset(updates_dir: Path, platform: str) -> Path | None:
    """Find a binary asset in updates_dir matching the target platform."""
    if not updates_dir.exists():
        return None

    plat = platform.lower()
    patterns = []
    if "win" in plat:
        patterns = ["*windows*.zip", "*win*.zip", "*win*.exe", "*.msi", "*.exe"]
    elif "mac" in plat or "darwin" in plat:
        patterns = ["*macos*.zip", "*mac*.zip", "*.dmg", "*.pkg"]
    elif "linux" in plat:
        patterns = ["*linux*.tar.gz", "*linux*.zip", "*.AppImage", "*.deb"]
    else:
        patterns = [f"*{plat}*"]

    for pat in patterns:
        for p in updates_dir.glob(pat):
            if p.is_file() and not p.name.endswith(".json") and not p.name.endswith(".part"):
                return p
    return None


def _match_github_asset(assets: list[dict[str, Any]], platform: str) -> dict[str, Any] | None:
    """Match the most appropriate release asset for the requested platform."""
    plat = platform.lower()

    if "win" in plat:
        # Prefer .zip for seamless in-place hot replacement (matching macOS and Linux); fallback to setup.exe
        for a in assets:
            name = a.get("name", "").lower()
            if ("win" in name or "windows" in name) and name.endswith(".zip"):
                return a
        for a in assets:
            name = a.get("name", "").lower()
            if ("win" in name or "windows" in name) and (name.endswith("setup.exe") or name.endswith(".exe") or name.endswith(".msi")):
                return a

    elif "mac" in plat or "darwin" in plat:
        # Prefer .zip for in-place app replacement; fallback to .dmg
        for a in assets:
            name = a.get("name", "").lower()
            if ("mac" in name or "darwin" in name) and name.endswith(".zip"):
                return a
        for a in assets:
            name = a.get("name", "").lower()
            if ("mac" in name or "darwin" in name) and name.endswith(".dmg"):
                return a

    elif "linux" in plat:
        # Prefer .tar.gz / .zip for portable update; fallback to .deb or .AppImage
        for a in assets:
            name = a.get("name", "").lower()
            if "linux" in name and (name.endswith(".tar.gz") or name.endswith(".zip")):
                return a
        for a in assets:
            name = a.get("name", "").lower()
            if "linux" in name and (name.endswith(".deb") or name.endswith(".appimage")):
                return a

    # Fallback to loose name match
    for a in assets:
        name = a.get("name", "").lower()
        if plat in name and not name.endswith(".txt") and not name.endswith(".sha256"):
            return a

    return None


async def _fetch_latest_github_release(force_refresh: bool = False) -> dict[str, Any] | None:
    """Fetch latest release info from GitHub, using memory cache and mirror fallbacks."""
    global _RELEASE_CACHE
    now = time.time()
    if not force_refresh and _RELEASE_CACHE["data"] and (now - _RELEASE_CACHE["time"] < GITHUB_CACHE_TTL):
        return _RELEASE_CACHE["data"]

    urls = [
        f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest",
        f"https://mirror.ghproxy.com/https://api.github.com/repos/{GITHUB_REPO}/releases/latest",
    ]

    try:
        import httpx
    except ImportError:
        return None

    headers = {
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "Memento-Server-Updater/1.0",
    }
    github_token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if github_token:
        headers["Authorization"] = f"Bearer {github_token}"

    async with httpx.AsyncClient(follow_redirects=True, timeout=8.0) as client:
        for url in urls:
            try:
                resp = await client.get(url, headers=headers)
                if resp.status_code == 200:
                    data = resp.json()
                    if isinstance(data, dict) and "tag_name" in data:
                        _RELEASE_CACHE["time"] = now
                        _RELEASE_CACHE["data"] = data
                        return data
            except Exception as e:
                logger.debug("Failed to fetch release from %s: %s", url, e)

    return _RELEASE_CACHE["data"]


@router.get("/check", response_model=UpdateCheckResponse)
async def check_update(
    platform: str = Query("windows", description="Target platform (windows/macos/linux)"),
    version: str = Query("1.0.0", description="Current client version"),
) -> UpdateCheckResponse:
    """Check if the server or upstream repository hosts a newer version of the client."""
    plat_lower = (platform or "").lower()
    if any(m in plat_lower for m in ("ios", "iphone", "ipad", "android", "mobile")):
        return UpdateCheckResponse(
            has_update=False,
            latest_version=version,
            current_version=version,
            title="Memento Mobile",
            release_notes="移动端请在 GitHub Release 发布页查看安装说明。",
        )

    updates_dir = _UPDATES_DIR
    version_file = updates_dir / "version.json"

    # 1. Read local static metadata if present
    local_meta: dict[str, Any] = {}
    if version_file.exists():
        try:
            with open(version_file, "r", encoding="utf-8") as f:
                local_meta = json.load(f)
        except Exception:
            local_meta = {}

    local_ver = str(local_meta.get("version", "")).strip().lstrip("vV")
    local_platform_asset = _find_platform_asset(updates_dir, platform)

    # 2. Query latest GitHub release (dynamic auto-discovery)
    gh_release = await _fetch_latest_github_release()

    gh_ver = ""
    gh_asset: dict[str, Any] | None = None
    if gh_release:
        raw_tag = str(gh_release.get("tag_name", "")).strip()
        gh_ver = raw_tag.lstrip("vV")
        assets = gh_release.get("assets", [])
        if isinstance(assets, list):
            gh_asset = _match_github_asset(assets, platform)

    # 3. Determine latest version: compare local vs GitHub
    use_github = False
    latest_ver = ""

    if gh_ver and local_ver:
        if _compare_semver(gh_ver, local_ver):
            latest_ver = gh_ver
            use_github = True
        else:
            latest_ver = local_ver
            use_github = False
    elif gh_ver:
        latest_ver = gh_ver
        use_github = True
    elif local_ver:
        latest_ver = local_ver
        use_github = False
    elif local_platform_asset:
        m = re.search(r"(\d+\.\d+\.\d+)", local_platform_asset.name)
        if m:
            latest_ver = m.group(1)

    if not latest_ver and not local_platform_asset:
        return UpdateCheckResponse(
            has_update=False,
            current_version=version,
            release_notes="服务端暂未托管更新包",
        )

    clean_current = version.strip().lstrip("vV")
    has_update = _compare_semver(latest_ver, clean_current) if latest_ver else (local_platform_asset is not None)

    title = f"Memento v{latest_ver}"
    release_notes = "修复已知问题并提升稳定性。"
    published_at = None
    asset_name = None
    asset_size = None
    sha256_val = None

    if use_github and gh_release:
        title = str(gh_release.get("name") or title)
        release_notes = str(gh_release.get("body") or release_notes)
        published_at = gh_release.get("published_at")
        if gh_asset:
            asset_name = gh_asset.get("name")
            asset_size = gh_asset.get("size")
    else:
        title = local_meta.get("title", title)
        release_notes = local_meta.get("release_notes", release_notes)
        published_at = local_meta.get("published_at")
        plat_meta = local_meta.get("platforms", {}).get(platform.lower(), {})
        if plat_meta and isinstance(plat_meta, dict):
            asset_name = plat_meta.get("asset_name")
            asset_size = plat_meta.get("size")
            sha256_val = plat_meta.get("sha256")

        if local_platform_asset:
            asset_name = local_platform_asset.name
            asset_size = local_platform_asset.stat().st_size
        elif gh_release:
            assets = gh_release.get("assets", [])
            exact_gh_asset = next((a for a in assets if a.get("name") == asset_name), None) if asset_name and isinstance(assets, list) else None
            matched = exact_gh_asset or gh_asset
            if matched and matched.get("size"):
                asset_size = matched.get("size")
                if not asset_name:
                    asset_name = matched.get("name")
                gh_asset = matched

    upstream_url = None
    if gh_asset:
        upstream_url = gh_asset.get("browser_download_url")

    download_url = None
    if asset_name:
        download_url = f"/api/system/update/download?file={asset_name}"

    return UpdateCheckResponse(
        has_update=has_update,
        latest_version=latest_ver or version,
        current_version=version,
        title=title,
        release_notes=release_notes,
        published_at=published_at,
        download_url=download_url,
        upstream_url=upstream_url,
        asset_name=asset_name,
        asset_size=asset_size,
        sha256=sha256_val,
    )


@router.get("/download")
async def download_update(
    file: str = Query(..., description="Asset filename to download"),
):
    """Download update asset file with directory traversal protection.
    
    If hosted locally on the server filesystem, serves it immediately via FileResponse.
    If not cached locally, instantly 302 redirects to upstream GitHub Release URL,
    avoiding blocking the server async event loop with heavy binary proxying.
    """
    # Sanitize filename: only allow safe alphanumeric, dots, dashes, underscores
    safe_name = os.path.basename(file)
    if not re.match(r"^[\w\.\-]+$", safe_name):
        raise HTTPException(status_code=400, detail="Invalid filename")

    file_path = _UPDATES_DIR / safe_name
    if file_path.exists() and file_path.is_file():
        return FileResponse(
            file_path,
            filename=safe_name,
            media_type="application/octet-stream",
            headers={
                "Cache-Control": "public, max-age=600",
                "Content-Disposition": f'attachment; filename="{safe_name}"',
            },
        )

    # Asset is not present in local filesystem: redirect (302) to upstream GitHub Releases
    tag = ""
    gh_release = _RELEASE_CACHE.get("data")
    if gh_release and "tag_name" in gh_release:
        tag = str(gh_release["tag_name"]).strip()

    if not tag:
        version_file = _UPDATES_DIR / "version.json"
        if version_file.exists():
            try:
                with open(version_file, "r", encoding="utf-8") as f:
                    meta = json.load(f)
                    tag = str(meta.get("version", "")).strip()
            except Exception:
                pass

    if not tag:
        m = re.search(r"[vV]?(\d+\.\d+\.\d+)", safe_name)
        if m:
            tag = m.group(1)

    tag_name = tag if tag.startswith("v") else (f"v{tag}" if tag else "v1.0.13")
    target_url = f"https://github.com/{GITHUB_REPO}/releases/download/{tag_name}/{safe_name}"
    logger.info("Local update asset '%s' not found on server disk, redirecting 302 to upstream: %s", safe_name, target_url)
    return RedirectResponse(url=target_url, status_code=302)


