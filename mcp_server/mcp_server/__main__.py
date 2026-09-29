"""Entry point for the MCP Memory Server.

Usage:
  # On a machine running the Memento collector: nothing to pass, the server URL
  # and device token are read from ~/.memento/collector.json (and re-read if the
  # token is rotated).
  memento-memory

  # Anywhere else: point it at a server with a collector token or a JWT.
  memento-memory --server https://mem.ihasy.com --token YOUR_TOKEN
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


def collector_config_path() -> Path:
    override = os.environ.get("MEMENTO_COLLECTOR_CONFIG")
    return Path(override) if override else Path.home() / ".memento" / "collector.json"


def read_collector_config() -> tuple[str | None, str | None]:
    """(server_url, token) from the local collector's config, if there is one."""
    try:
        data = json.loads(collector_config_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None, None
    return data.get("server_url") or None, data.get("token") or None


def main():
    parser = argparse.ArgumentParser(
        description="Memento MCP Server — personal AI memory for all tools",
    )
    parser.add_argument("--server", help="Memento server URL (e.g. https://mem.ihasy.com)")
    parser.add_argument("--token", help="Collector token or JWT")
    args = parser.parse_args()

    cfg_url, cfg_token = read_collector_config()
    server_url = args.server or os.environ.get("MEMENTO_SERVER_URL") or cfg_url
    token = args.token or os.environ.get("MEMENTO_SERVER_TOKEN") or cfg_token

    from .server import mcp, init_server

    if not (server_url and token):
        print("Error: no server/token. Sign in with the Memento app (it writes ~/.memento/collector.json),", file=sys.stderr)
        print("or run: memento-memory --server https://mem.ihasy.com --token YOUR_TOKEN", file=sys.stderr)
        sys.exit(1)
    init_server(server_url=server_url, token=token, token_loader=lambda: read_collector_config()[1])

    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
