# Donna

Donna is a lightweight macOS assistant with a floating chat panel. It can talk to your Apple apps (Notes, Contacts, Calendar, Mail, Reminders, Maps) via MCP (Model Context Protocol).

## Features
- Chat UI with streaming responses
- MCP integration to discover tools, read resources, and call actions
- Apple MCP server support (via `bunx apple-mcp`)
- Slash commands:
  - `/tools` — list available MCP tools
  - `/schema <toolName>` — show a tool’s input schema
  - `/call <toolName> {json}` — invoke a tool directly

## Requirements
- macOS 13+
- Xcode 15+
- Bun (for Apple MCP server): `brew install bun`

## Using Donna
- Type requests in the input box (e.g., “List my notes from today”).
- Use `/tools` to see what MCP tools are available.
- Use `/schema <toolName>` to inspect parameters for a tool.

## How it works (high level)
- On launch, Donna loads MCP server configs and connects to those marked enabled.
- First connection may ask for permissions (Notes, Contacts, Calendar, Mail, Reminders). Grant to enable capabilities.
