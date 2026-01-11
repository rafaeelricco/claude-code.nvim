# claudecode.nvim (Headless)

A minimal Neovim plugin that implements a WebSocket server for Claude CLI connection.

## Overview

This is a stripped-down version focused purely on the WebSocket MCP connection. All UI features (terminal, diff views, selection tracking, file explorer integration) have been removed.

**What it does:**
- Creates a WebSocket server on a random port
- Writes a lock file to `~/.claude/ide/[port].lock` for Claude CLI discovery
- Handles MCP protocol (initialize, tools/list, tools/call)
- Returns empty tools list (no tools implemented)

## Installation

```lua
{
  "your-repo/claudecode.nvim",
  config = true,
}
```

## Configuration

```lua
require("claudecode").setup({
  port_range = { min = 10000, max = 65535 },
  auto_start = true,  -- Start server automatically
  log_level = "info", -- "trace", "debug", "info", "warn", "error"
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:ClaudeCodeStart` | Start the WebSocket server |
| `:ClaudeCodeStop` | Stop the WebSocket server |
| `:ClaudeCodeStatus` | Show server status and connection info |

Other commands exist for compatibility but are disabled:
- `:ClaudeCode`, `:ClaudeCodeFocus`, `:ClaudeCodeOpen`, `:ClaudeCodeClose`
- `:ClaudeCodeSend`, `:ClaudeCodeAdd`, `:ClaudeCodeTreeAdd`
- `:ClaudeCodeDiffAccept`, `:ClaudeCodeDiffDeny`

## API

```lua
local claudecode = require("claudecode")

-- Setup with options
claudecode.setup({ log_level = "debug" })

-- Manual server control
claudecode.start()
claudecode.stop()

-- Status checks
claudecode.is_running()         -- boolean
claudecode.get_port()           -- number or nil
claudecode.is_claude_connected() -- boolean
claudecode.get_version()        -- version table
```

## How It Works

1. Server starts and binds to a random port in the configured range
2. Lock file is created at `~/.claude/ide/[port].lock` with:
   - `pid`: Process ID
   - `workspaceFolders`: Current working directory
   - `ideName`: "Neovim"
   - `transport`: "ws"
   - `authToken`: UUID v4 authentication token
3. Claude CLI reads the lock file and connects via WebSocket
4. Authentication is validated via `x-claude-code-ide-authorization` header
5. MCP protocol messages are exchanged (JSON-RPC 2.0 over WebSocket)

## Requirements

- Neovim >= 0.8.0

## License

[MIT](LICENSE)
