# CLAUDE.md

This file provides context for Claude Code when working with this codebase.

## Project Overview

claudecode.nvim - A Neovim plugin that implements a WebSocket server for Claude CLI connection via MCP protocol. Built with pure Lua and minimal dependencies (optional snacks.nvim for terminal).

## Architecture Overview

### Core Components

1. **WebSocket Server** (`lua/claudecode/server/`) - Pure Neovim implementation using vim.loop, RFC 6455 compliant
2. **Lock File System** (`lua/claudecode/lockfile.lua`) - Creates discovery files for Claude CLI at `~/.claude/ide/`
3. **Configuration** (`lua/claudecode/config.lua`) - Configuration validation
4. **Logger** (`lua/claudecode/logger.lua`) - Debugging output
5. **MCP Tools** (`lua/claudecode/tools/`) - Tools exposed to Claude CLI
6. **Selection** (`lua/claudecode/selection.lua`) - Visual selection tracking and broadcasting
7. **Diff** (`lua/claudecode/diff.lua`) - Native diff views for proposed changes
8. **Terminal** (`lua/claudecode/terminal.lua`) - Terminal management via snacks.nvim (optional)

### WebSocket Server Implementation

- **TCP Server**: `server/tcp.lua` handles port binding and connections
- **Handshake**: `server/handshake.lua` processes HTTP upgrade requests with authentication
- **Frame Processing**: `server/frame.lua` implements RFC 6455 WebSocket frames
- **Client Management**: `server/client.lua` manages individual connections
- **Utils**: `server/utils.lua` provides base64, SHA-1, XOR operations in pure Lua
- **MCP Protocol**: `server/init.lua` handles JSON-RPC 2.0 over WebSocket

### Authentication System

- **UUID v4 Tokens**: Generated per session with enhanced entropy
- **Header-based Auth**: Uses `x-claude-code-ide-authorization` header
- **Lock File Discovery**: Tokens stored in `~/.claude/ide/[port].lock` for Claude CLI
- **MCP Compliance**: Follows official Claude Code IDE authentication protocol

### File Structure

```
lua/claudecode/
├── init.lua         - Main entry point and setup
├── config.lua       - Configuration management
├── lockfile.lua     - Lock file creation/removal
├── logger.lua       - Logging utility
├── selection.lua    - Visual selection tracking and broadcasting
├── buffer_resolver.lua - Resolve/materialize context from non-file buffers
├── diff.lua         - Native diff view management
├── terminal.lua     - Terminal management (requires snacks.nvim)
├── server/
│   ├── init.lua     - MCP JSON-RPC 2.0 protocol handler
│   ├── tcp.lua      - TCP server, port binding
│   ├── handshake.lua - WebSocket upgrade, authentication
│   ├── frame.lua    - WebSocket frame encoding/decoding
│   ├── client.lua   - Client connection state machine
│   └── utils.lua    - Pure Lua crypto primitives
└── tools/
    ├── init.lua     - Tool registry and dispatcher
    ├── open_file.lua - openFile tool
    ├── selection.lua - getCurrentSelection tool
    ├── editors.lua  - getOpenEditors tool
    └── diff.lua     - openDiff tool

plugin/claudecode.lua - Plugin loader
```

### MCP Tools

The following tools are exposed to Claude CLI:

| Tool | Description |
|------|-------------|
| `openFile` | Open a file at optional line/column |
| `getCurrentSelection` | Get current visual selection text and location |
| `getOpenEditors` | List all open buffers with modification status |
| `openDiff` | Open native diff view for proposed changes |

## Technical Requirements

- Neovim >= 0.8.0
- Uses Neovim built-ins (vim.loop, vim.json, vim.schedule)
- Optional: snacks.nvim for terminal integration

## Testing

Run locally with clean Neovim environment:

```bash
nvim --clean --headless -c "set rtp+=." -c "lua require('claudecode').setup({ auto_start = false })" -c "lua print(require('claudecode').start())" -c "qa!"
```

Test WebSocket connection manually:

```bash
# Test valid auth token (should succeed)
websocat ws://localhost:PORT --header "x-claude-code-ide-authorization: $(cat ~/.claude/ide/*.lock | jq -r .authToken)"

# Test invalid auth token (should fail)
websocat ws://localhost:PORT --header "x-claude-code-ide-authorization: invalid-token"
```

## API

```lua
local claudecode = require("claudecode")

-- Setup with options
claudecode.setup({
  port_range = { min = 10000, max = 65535 },
  auto_start = true,
  log_level = "info",
})

-- Manual server control
claudecode.start()   -- Returns: success, port_or_error
claudecode.stop()    -- Returns: success, error

-- Status checks
claudecode.is_running()          -- boolean
claudecode.get_port()            -- number or nil
claudecode.is_claude_connected() -- boolean
claudecode.get_version()         -- version table
```

## Commands

### Server Commands
| Command | Description |
|---------|-------------|
| `:ClaudeCodeStart` | Start the WebSocket server |
| `:ClaudeCodeStop` | Stop the WebSocket server |
| `:ClaudeCodeStatus` | Show server status and connection info |

### Terminal Commands (requires snacks.nvim)
| Command | Description |
|---------|-------------|
| `:ClaudeCode [args]` | Toggle Claude terminal (args passed to claude CLI) |
| `:ClaudeCodeOpen [args]` | Open Claude terminal |
| `:ClaudeCodeFocus` | Focus existing Claude terminal |
| `:ClaudeCodeClose` | Close Claude terminal |

### Selection Commands
| Command | Description |
|---------|-------------|
| `:ClaudeCodeSend` | Send current visual selection to Claude (works from non-file buffers — NeoGit, quickfix, terminal — via the buffer resolver) |
| `:ClaudeCodeAdd [file]` | Add file to Claude context (% for current) |
| `:ClaudeCodeAddBuffer` | Materialize the current buffer (or range) to a temp file and add it to Claude context |
| `:ClaudeCodeTreeAdd` | Add selected file from tree explorer |

### Diff Commands
| Command | Description |
|---------|-------------|
| `:ClaudeCodeDiffAccept` | Accept proposed diff changes |
| `:ClaudeCodeDiffDeny` | Reject proposed diff changes |

## Release Process

When updating the version number, update `lua/claudecode/init.lua`:

```lua
M.version = {
  major = 0,
  minor = 2,
  patch = 0,
  prerelease = nil,
}
```

## Security Considerations

- WebSocket server only accepts local connections (127.0.0.1)
- Authentication tokens are UUID v4 with enhanced entropy
- Lock files created at `~/.claude/ide/[port].lock` for Claude CLI discovery

## Logging

Enable detailed logging:

```lua
require("claudecode").setup({
  log_level = "debug"  -- Shows auth token generation, validation, and failures
})
```
