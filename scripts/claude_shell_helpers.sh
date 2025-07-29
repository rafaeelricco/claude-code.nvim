#!/usr/bin/env bash
# Source this file in your .zshrc or .bashrc to add Claude Code helper functions
# to your interactive shell
#
# Example usage:
#   echo 'source /path/to/claude_shell_helpers.sh' >> ~/.zshrc
#
# Then in your shell:
#   $ claude_port
#   $ claude_get_selection
#   $ claude_open_file /path/to/file.txt

# Get the script's directory, handling sourced scripts
if [[ -n $0 && $0 != "-bash" && $0 != "-zsh" ]]; then
  CLAUDE_LIB_DIR="$(dirname "$(realpath "$0")")"
else
  # Fallback when being sourced in a shell
  CLAUDE_LIB_DIR="${HOME}/.claude/bin"
fi

# Source the main library
# shellcheck source=./lib_claude.sh
source "$CLAUDE_LIB_DIR/lib_claude.sh"

# Set default log directory relative to home
export CLAUDE_LOG_DIR="$HOME/.claude/logs"
mkdir -p "$CLAUDE_LOG_DIR" 2>/dev/null

# Function to get and print Claude Code port
claude_port() {
  find_claude_lockfile
}

# Function to get websocket URL
claude_ws_url() {
  get_claude_ws_url
}

# Function to check if Claude Code is running
claude_running() {
  if claude_is_running; then
    local port
    port=$(find_claude_lockfile 2>/dev/null)
    echo "Claude Code is running (port: $port)"
    return 0
  else
    echo "Claude Code is not running"
    return 1
  fi
}

# Function to get current selection
claude_get_selection() {
  if claude_is_running; then
    local response
    response=$(get_current_selection)

    # Pretty print the whole response if -v/--verbose flag is provided
    if [[ $1 == "-v" || $1 == "--verbose" ]]; then
      echo "$response" | jq .
      return
    fi

    # Otherwise just output the selection text
    local selection
    selection=$(echo "$response" | jq -r '.result.text // "No text selected"')
    if [[ $selection != "No text selected" && $selection != "null" ]]; then
      echo "$selection"
    else
      echo "No text currently selected"
    fi
  else
    echo "Error: Claude Code is not running" >&2
    return 1
  fi
}

# Function to open a file in Claude Code
claude_open_file() {
  if [ -z "$1" ]; then
    echo "Usage: claude_open_file <path_to_file>" >&2
    return 1
  fi

  local file_path="$1"

  # Convert to absolute path if relative
  if [[ $file_path != /* ]]; then
    file_path="$(realpath "$file_path" 2>/dev/null)"
    if ! realpath "$file_path" &>/dev/null; then
      echo "Error: Invalid file path" >&2
      return 1
    fi
  fi

  if [ ! -f "$file_path" ]; then
    echo "Error: File does not exist: $file_path" >&2
    return 1
  fi

  if claude_is_running; then
    open_file "$file_path" >/dev/null
    echo "Opened: $file_path"
  else
    echo "Error: Claude Code is not running" >&2
    return 1
  fi
}

# Function to list available tools
claude_list_tools() {
  if claude_is_running; then
    local response
    response=$(list_claude_tools)

    # Pretty print the whole response if -v/--verbose flag is provided
    if [[ $1 == "-v" || $1 == "--verbose" ]]; then
      echo "$response" | jq .
      return
    fi

    # Otherwise just list tool names
    echo "$response" | jq -r '.result.tools[].name' 2>/dev/null | sort
  else
    echo "Error: Claude Code is not running" >&2
    return 1
  fi
}

# Function to send a custom message
claude_send() {
  if [ $# -lt 2 ]; then
    echo "Usage: claude_send <method> <params_json> [request_id]" >&2
    echo "Example: claude_send 'getCurrentSelection' '{}' 'my-id'" >&2
    return 1
  fi

  local method="$1"
  local params="$2"
  local id="${3:-$(uuidgen)}"

  if claude_is_running; then
    local message
    message=$(create_message "$method" "$params" "$id")

    local response
    response=$(send_claude_message "$message")
    echo "$response" | jq .
  else
    echo "Error: Claude Code is not running" >&2
    return 1
  fi
}

# Launch the interactive tool
claude_interactive() {
  "$CLAUDE_LIB_DIR/claude_interactive.sh"
}

# Print help for shell functions
claude_help() {
  cat <<EOL
Claude Code Shell Helper Functions

Available commands:
  claude_port              - Get the port Claude Code is running on
  claude_ws_url            - Get the WebSocket URL for Claude Code
  claude_running           - Check if Claude Code is running
  claude_get_selection     - Get the current editor selection
  claude_get_selection -v  - Get detailed selection info (verbose)
  claude_open_file <path>  - Open a file in Claude Code
  claude_list_tools        - List available tools
  claude_list_tools -v     - List tools with details (verbose)
  claude_send <method> <params> [id] - Send a custom JSON-RPC message
  claude_interactive       - Launch the interactive CLI
  claude_help              - Show this help message

Examples:
  $ claude_port
  $ claude_get_selection
  $ claude_open_file ~/project/src/main.js
  $ claude_send 'getCurrentSelection' '{}'
EOL
}

# Check if sourced in an interactive shell
if [[ $- == *i* ]]; then
  echo "Claude Code shell helpers loaded. Type 'claude_help' for available commands."
fi
