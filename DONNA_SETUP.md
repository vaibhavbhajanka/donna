# Donna Setup Guide - Fixing Common Issues

## Issues Found and Fixed

### 1. ✅ Missing Bun Installation
**Problem**: Donna requires Bun to run the Apple MCP server, but it wasn't installed.
**Solution**: Installed Bun using the official installer.

### 2. ✅ Incorrect Bunx Path
**Problem**: The code hardcoded bunx path as `/opt/homebrew/bin/bunx` (macOS Homebrew), but in this environment it's at `/home/ubuntu/.bun/bin/bunx`.
**Solution**: Updated `MCPTransportFactory.swift` to dynamically detect bunx location across different environments.

### 3. ✅ Missing Environment Configuration
**Problem**: No `.donna.env` file existed for API key configuration.
**Solution**: Created `~/.donna.env` with placeholder for OpenAI API key.

## Required Setup Steps

### 1. Configure OpenAI API Key
Edit the `~/.donna.env` file and add your actual OpenAI API key:
```bash
# Replace 'your_api_key_here' with your actual OpenAI API key
OPENAI_API_KEY=sk-your-actual-api-key-here
```

### 2. Grant Permissions (macOS only)
When you first run Donna, macOS will ask for permissions to access:
- Contacts
- Calendar  
- Notes
- Mail
- Reminders
- Maps

Grant these permissions for full functionality.

### 3. Build and Run
If using Xcode:
```bash
open Donna.xcodeproj
# Build and run from Xcode (Cmd+R)
```

## How Donna Works

1. **Activation**: The app starts with a floating panel
2. **MCP Integration**: Connects to Apple MCP server via `bunx apple-mcp@latest`
3. **LLM Processing**: Uses OpenAI API (or local echo if no key) to process commands
4. **Tool Execution**: Executes MCP tools to interact with Apple services

## Testing Commands

Try these commands in Donna:
- `/tools` - List available MCP tools
- `List my notes from today`
- `Show my calendar for tomorrow`
- `Find contacts named John`

## Troubleshooting

### If MCP Connection Fails
- Check that Bun is installed: `bun --version`
- Verify bunx works: `bunx --no-cache apple-mcp@latest --help`
- Check logs in `~/Library/Application Support/Donna/donna.log`

### If LLM Responses Are Generic
- Ensure your OpenAI API key is set in `~/.donna.env`
- Restart the app after adding the API key

### If No Tools Are Available
- Grant macOS permissions for Contacts, Calendar, etc.
- Check MCP server connection in the app logs