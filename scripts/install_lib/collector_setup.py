"""Set up this machine's collector against the freshly-started server.

The collector is the Node daemon in packages/daemon (the same one the Memento
Desktop app runs). With Node 20+ available it is built from this checkout and
installed as a login service (launchd / systemd / Windows Run key); otherwise
the device is configured and the desktop app picks it up when installed.

Also provides `deep_uninstall()` for `./install.sh uninstall --all`: stops the
daemon service, removes the retired pip collector if present, ~/.memento config,
logs, and MCP server entries from ~/.claude.json, Cursor, Codex, etc.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from pathlib import Path

from .platform_utils import (
    IS_LINUX, IS_MAC, IS_WINDOWS, REPO_ROOT, find_python, info, ok, warn, which,
)

DESKTOP_RELEASES = "https://github.com/ddong8/memento/releases/latest"
DAEMON_CLI = REPO_ROOT / "packages" / "daemon" / "dist" / "cli.js"


def write_device_config(token: str, server_url: str, web_url: str) -> Path:
    """Merge server, web URL and token into ~/.memento/collector.json (keeps the device id)."""
    path = Path.home() / ".memento" / "collector.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    data: dict = {}
    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            data = {}
    data.update({"server_url": server_url, "web_url": web_url, "token": token})
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
    return path


def _node_major() -> int | None:
    node = which("node")
    if not node:
        return None
    r = subprocess.run([node, "--version"], capture_output=True, text=True)
    m = re.match(r"v(\d+)", r.stdout.strip())
    return int(m.group(1)) if m else None


def _npm(*args: str) -> None:
    npm = which("npm")
    if not npm:
        raise RuntimeError("npm not found")
    subprocess.run([npm, *args], check=True, cwd=str(REPO_ROOT), shell=IS_WINDOWS)


def build_daemon() -> None:
    """Install the daemon's dependencies and compile it (idempotent; used by update too)."""
    _npm("ci", "--workspace", "@memento/daemon", "--workspace", "@memento/core", "--include-workspace-root")
    _npm("run", "build", "-w", "@memento/daemon")


def install_collector(token: str, server_url: str = "http://localhost:8001",
                      web_url: str = "http://localhost:3001") -> None:
    """Configure this device and run the Node daemon as a login service when Node is available."""
    cfg = write_device_config(token, server_url, web_url)
    ok(f"Device configured → {server_url} ({cfg})")

    major = _node_major()
    if major is None or major < 20:
        warn("Node.js 20+ not found, so the collector wasn't installed as a service.")
        info(f"Install Memento ({DESKTOP_RELEASES}); it reads {cfg} and signs in on its own.")
        info("Or install Node.js 20+ and run `./install.sh update` to set up the headless collector.")
        return

    info("Building the collector daemon…")
    build_daemon()
    node = which("node") or "node"
    subprocess.run([node, str(DAEMON_CLI), "install-service"], check=True, cwd=str(REPO_ROOT))
    ok("Collector daemon installed as a background service.")
    info("If the Memento app is also running, only one of them collects (they share ~/.memento).")


def daemon_service_installed() -> bool:
    return DAEMON_CLI.exists()


# ─────────────────────────────────────────────────────────────
# Deep uninstall
# ─────────────────────────────────────────────────────────────

# Old MCP key (pre-rebrand) + new one — clean both on uninstall
_MCP_KEYS = ("memento-memory", "daily-report-memory")


def _remove_mcp_entry(config_path: Path) -> None:
    """Strip memento-memory / daily-report-memory entries from a JSON MCP config."""
    if not config_path.exists():
        return
    try:
        data = json.loads(config_path.read_text())
    except Exception:
        return
    changed = False
    if isinstance(data, dict) and isinstance(data.get("mcpServers"), dict):
        for key in _MCP_KEYS:
            if key in data["mcpServers"]:
                del data["mcpServers"][key]
                changed = True
                ok(f"Removed '{key}' from {config_path.name}")
    if changed:
        config_path.write_text(json.dumps(data, indent=2))


def _remove_codex_mcp(config_path: Path) -> None:
    """Strip [mcp_servers.memento-memory] / [mcp_servers.daily-report-memory] from Codex TOML."""
    if not config_path.exists():
        return
    text = config_path.read_text()
    for key in _MCP_KEYS:
        header = f"[mcp_servers.{key}]"
        if header not in text:
            continue
        # Remove the header line through the next blank line or next [section]
        lines = text.splitlines(keepends=True)
        out: list[str] = []
        skipping = False
        for line in lines:
            stripped = line.strip()
            if stripped == header:
                skipping = True
                continue
            if skipping:
                if stripped.startswith("[") and stripped.endswith("]"):
                    skipping = False
                    out.append(line)
                elif stripped == "":
                    skipping = False
            else:
                out.append(line)
        text = "".join(out)
        ok(f"Removed codex mcp entry '{key}' from {config_path.name}")
    config_path.write_text(text)


def _pip_uninstall(package: str) -> None:
    try:
        py = find_python()
    except Exception:
        return
    r = subprocess.run(
        [py, "-m", "pip", "show", package],
        capture_output=True,
    )
    if r.returncode != 0:
        return  # not installed
    subprocess.run(
        [py, "-m", "pip", "uninstall", "-y", package],
        check=False,
    )
    ok(f"pip uninstalled {package}")


def uninstall_daemon_service() -> None:
    """Remove the Node daemon's login service, if this checkout installed one."""
    node = which("node")
    if node and DAEMON_CLI.exists():
        info("Removing the collector daemon service…")
        subprocess.run([node, str(DAEMON_CLI), "uninstall-service"], check=False, cwd=str(REPO_ROOT))


def deep_uninstall() -> None:
    """Everything collector-side: services, retired pip packages, config, logs, MCP entries."""
    uninstall_daemon_service()
    # The retired Python collector, if an older install left it behind.
    for cmd in ("memento-collector", "daily-report-collector"):
        if which(cmd):
            info(f"Stopping collector service ({cmd})…")
            subprocess.run([cmd, "uninstall"], check=False)

    # pip uninstall all name variants (new brand + transitional + legacy)
    info("Uninstalling pip packages…")
    for pkg in ("memento-brain-collector", "memento-brain-memory", "memento-brain",
                "memento-collector", "memento-memory",
                "daily-report-collector", "daily-report-memory"):
        _pip_uninstall(pkg)

    # Remove data dirs (new + legacy)
    for d in (Path.home() / ".memento", Path.home() / ".daily-report"):
        if d.exists():
            shutil.rmtree(d, ignore_errors=True)
            ok(f"Removed {d}/")

    # Remove collector logs (new + legacy paths)
    log_candidates: list[Path] = []
    if IS_MAC:
        log_candidates += [
            Path.home() / "Library" / "Logs" / "memento",
            Path.home() / "Library" / "Logs" / "daily_report",
        ]
    elif IS_LINUX:
        log_candidates += [
            Path.home() / ".local" / "share" / "memento" / "logs",
            Path.home() / ".local" / "share" / "daily_report" / "logs",
        ]
    elif IS_WINDOWS:
        local = Path(os.environ.get("LOCALAPPDATA", str(Path.home())))
        log_candidates += [
            local / "memento" / "logs",
            local / "daily_report" / "logs",
        ]
    for logs in log_candidates:
        if logs.exists():
            shutil.rmtree(logs, ignore_errors=True)
            ok(f"Removed logs {logs}/")

    # Strip MCP server entries from AI tool configs
    info("Cleaning MCP configs in AI tool configs…")
    home = Path.home()
    for p in [
        home / ".claude.json",
        home / ".cursor" / "mcp.json",
        home / ".config" / "windsurf" / "mcp.json",
        home / "Library" / "Application Support" / "antigravity" / "mcp.json",
    ]:
        _remove_mcp_entry(p)

    # Codex uses TOML
    _remove_codex_mcp(home / ".codex" / "config.toml")
