"""Client auto-update distribution API.

Serves update metadata and client packages directly from the Memento server,
enabling intranet/self-hosted automatic client upgrades without external GitHub dependencies.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse
from pydantic import BaseModel

router = APIRouter(prefix="/api/system/update", tags=["system-update"])

# Storage candidates for update packages
_CANDIDATES = [
    Path(os.environ.get("MEMENTO_UPDATES_DIR", "")) if os.environ.get("MEMENTO_UPDATES_DIR") else None,
    Path("/app/data/updates"),
    Path(__file__).resolve().parents[3] / "data" / "updates",
]
_UPDATES_DIR = next((p for p in _CANDIDATES if p and p.exists()), _CANDIDATES[-1])


class UpdateCheckResponse(BaseModel):
    has_update: bool
    latest_version: str = ""
    current_version: str = ""
    title: str = ""
    release_notes: str = ""
    published_at: str | None = None
    download_url: str | None = None
    asset_name: str | None = None
    asset_size: int | None = None
    sha256: str | None = None


def _compare_semver(target: str, current: str) -> bool:
    """Return True if target > current."""
    if not target:
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
            if p.is_file() and not p.name.endswith(".json"):
                return p
    return None


@router.get("/check", response_model=UpdateCheckResponse)
async def check_update(
    platform: str = Query("windows", description="Target platform (windows/macos/linux)"),
    version: str = Query("1.0.0", description="Current client version"),
) -> UpdateCheckResponse:
    """Check if the server hosts a newer version of the client for the requested platform."""
    updates_dir = _UPDATES_DIR
    version_file = updates_dir / "version.json"

    meta: dict[str, Any] = {}
    if version_file.exists():
        try:
            with open(version_file, "r", encoding="utf-8") as f:
                meta = json.load(f)
        except Exception:
            meta = {}

    latest_ver = str(meta.get("version", "")).strip()
    platform_asset = _find_platform_asset(updates_dir, platform)

    # If no explicit version in version.json, but an asset exists, derive version or assume update available
    if not latest_ver and platform_asset:
        m = re.search(r"(\d+\.\d+\.\d+)", platform_asset.name)
        if m:
            latest_ver = m.group(1)

    if not latest_ver and not platform_asset:
        return UpdateCheckResponse(
            has_update=False,
            current_version=version,
            release_notes="服务端暂未托管更新包",
        )

    has_update = _compare_semver(latest_ver, version) if latest_ver else (platform_asset is not None)

    asset_name = None
    asset_size = None
    sha256_val = None

    # Check platforms entry in version.json
    plat_meta = meta.get("platforms", {}).get(platform.lower(), {})
    if plat_meta and isinstance(plat_meta, dict):
        asset_name = plat_meta.get("asset_name")
        asset_size = plat_meta.get("size")
        sha256_val = plat_meta.get("sha256")

    if not asset_name and platform_asset:
        asset_name = platform_asset.name
        asset_size = platform_asset.stat().st_size

    download_url = None
    if asset_name:
        download_url = f"/api/system/update/download?file={asset_name}"

    return UpdateCheckResponse(
        has_update=has_update,
        latest_version=latest_ver or version,
        current_version=version,
        title=meta.get("title", f"Memento v{latest_ver}"),
        release_notes=meta.get("release_notes", "修复已知问题并提升稳定性。"),
        published_at=meta.get("published_at"),
        download_url=download_url,
        asset_name=asset_name,
        asset_size=asset_size,
        sha256=sha256_val,
    )


@router.get("/download")
async def download_update(
    file: str = Query(..., description="Asset filename to download"),
) -> FileResponse:
    """Download update asset file with directory traversal protection."""
    # Sanitize filename: only allow safe alphanumeric, dots, dashes, underscores
    safe_name = os.path.basename(file)
    if not re.match(r"^[\w\.\-]+$", safe_name):
        raise HTTPException(status_code=400, detail="Invalid filename")

    file_path = _UPDATES_DIR / safe_name
    if not file_path.exists() or not file_path.is_file():
        # Attempt to fetch from upstream GitHub release and cache locally on the server
        version_file = _UPDATES_DIR / "version.json"
        tag = ""
        if version_file.exists():
            try:
                with open(version_file, "r", encoding="utf-8") as f:
                    meta = json.load(f)
                    tag = str(meta.get("version", "")).strip()
            except Exception:
                pass

        if tag:
            tag_name = tag if tag.startswith("v") else f"v{tag}"
            upstream_url = f"https://github.com/ddong8/memento/releases/download/{tag_name}/{safe_name}"
            try:
                import httpx
                _UPDATES_DIR.mkdir(parents=True, exist_ok=True)
                tmp_file = _UPDATES_DIR / f"{safe_name}.part"
                async with httpx.AsyncClient(follow_redirects=True, timeout=120.0) as client:
                    async with client.stream("GET", upstream_url) as resp:
                        if resp.status_code == 200:
                            with open(tmp_file, "wb") as out_f:
                                async for chunk in resp.aiter_bytes():
                                    out_f.write(chunk)
                            tmp_file.replace(file_path)
            except Exception as e:
                if tmp_file.exists():
                    tmp_file.unlink(missing_ok=True)

    if not file_path.exists() or not file_path.is_file():
        raise HTTPException(status_code=404, detail="Update asset not found")

    return FileResponse(
        file_path,
        filename=safe_name,
        media_type="application/octet-stream",
        headers={
            "Cache-Control": "public, max-age=600",
            "Content-Disposition": f'attachment; filename="{safe_name}"',
        },
    )
