"""Entry point for the MCP Memory Server.

Usage:
  # On a machine running the Memento collector: nothing to pass, the server URL
  # and device token are read from ~/.memento/collector.json (and re-read if the
  # token is rotated).
  memento-memory

  # Remote mode (recommended — no DB needed, works anywhere):
  memento-memory --server https://mem.ihasy.com --token YOUR_JWT_TOKEN

  # Direct DB mode (local dev / self-hosted):
  memento-memory --db-url postgresql+asyncpg://user:pass@host:port/memento
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
    parser.add_argument("--token", help="JWT token for authentication")
    parser.add_argument("--db-url", help="PostgreSQL connection URL (for direct DB mode)")
    args = parser.parse_args()

    server_url = args.server or os.environ.get("MEMENTO_SERVER_URL")
    token = args.token or os.environ.get("MEMENTO_SERVER_TOKEN")
    db_url = args.db_url or os.environ.get("MEMENTO_DATABASE_URL")
    if not db_url:
        cfg_url, cfg_token = read_collector_config()
        server_url = server_url or cfg_url
        token = token or cfg_token

    from .server import mcp, init_server

    if server_url and token:
        init_server(server_url=server_url, token=token, token_loader=lambda: read_collector_config()[1])
    elif db_url:
        init_server(db_url=db_url)
    else:
        print("Error: Either --server/--token or --db-url is required.", file=sys.stderr)
        print("\nRemote mode (recommended):", file=sys.stderr)
        print("  memento-memory --server https://mem.ihasy.com --token YOUR_TOKEN", file=sys.stderr)
        print("\nDirect DB mode:", file=sys.stderr)
        print("  memento-memory --db-url postgresql+asyncpg://...", file=sys.stderr)
        sys.exit(1)

    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
