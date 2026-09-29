# Memento MCP Server (Python)

Personal AI memory powered by your Memento data, over MCP (stdio). It calls the
Memento server's API; no database access is needed.

> The Memento desktop app ships a TypeScript version of this server
> (`packages/mcp` in the repo) and shows ready-to-copy setup for Claude Code and
> Codex. This package stays for existing `pip` installs.

## Usage

```bash
pip install memento-brain-memory

# On a machine signed in to Memento: server and token come from ~/.memento/collector.json
memento-memory

# Anywhere else
memento-memory --server https://mem.ihasy.com --token YOUR_TOKEN
```

## Claude Code

```json
{
  "mcpServers": {
    "memento-memory": { "command": "memento-memory" }
  }
}
```
