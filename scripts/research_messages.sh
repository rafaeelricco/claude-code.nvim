#!/usr/bin/env bash

# research_messages.sh - Script to analyze JSON-RPC messages from Claude Code VSCode extension
# This script connects to a running Claude Code VSCode instance and logs all JSON-RPC messages
# for analysis.

set -e

# Source the library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib_claude.sh
source "$SCRIPT_DIR/lib_claude.sh"

# Configuration
TIMEOUT=30                              # How long to listen for messages (seconds)
LOG_FILE="claude_messages.jsonl"        # File to log all JSON-RPC messages
PRETTY_LOG="claude_messages_pretty.txt" # File to log prettified messages
WEBSOCKET_PORT=""                       # Will be detected automatically

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  -p | --port)
    WEBSOCKET_PORT="$2"
    shift 2
    ;;
  -t | --timeout)
    TIMEOUT="$2"
    shift 2
    ;;
  -l | --log)
    LOG_FILE="$2"
    shift 2
    ;;
  *)
    echo "Unknown option: $1"
    echo "Usage: $0 [-p|--port PORT] [-t|--timeout SECONDS] [-l|--log LOGFILE]"
    exit 1
    ;;
  esac
done

# Get WebSocket port if not provided
if [ -z "$WEBSOCKET_PORT" ]; then
  # Use library function to find the port
  WEBSOCKET_PORT=$(find_claude_lockfile)
  echo "Found Claude Code running on port: $WEBSOCKET_PORT"
fi

# Create directory for logs
LOG_DIR=$(dirname "$LOG_FILE")
if [ ! -d "$LOG_DIR" ] && [ "$LOG_DIR" != "." ]; then
  mkdir -p "$LOG_DIR"
fi

# MCP connection message
MCP_CONNECT='{
  "jsonrpc": "2.0",
  "id": "1",
  "method": "mcp.connect",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {
      "tools": {}
    },
    "clientInfo": {
      "name": "research-client",
      "version": "1.0.0"
    }
  }
}'

# Function to send a test message and see what happens
send_test_message() {
  local method="$1"
  local params="$2"
  local id="$3"

  local message="{\"jsonrpc\":\"2.0\",\"id\":\"$id\",\"method\":\"$method\",\"params\":$params}"
  echo "Sending test message: $message"
  echo "$message" | websocat -n1 "ws://127.0.0.1:$WEBSOCKET_PORT/"
  echo
}

# Clear previous log files
true >"$LOG_FILE"
true >"$PRETTY_LOG"

# Now that we have the port, display connection information
echo "Connecting to WebSocket server at ws://127.0.0.1:$WEBSOCKET_PORT/"
echo
echo "Will listen for $TIMEOUT seconds and log messages to $LOG_FILE"
echo "A prettified version will be written to $PRETTY_LOG"
echo

# Use websocat to connect and log all messages
(
  # First send the connection message
  echo "$MCP_CONNECT"

  # Keep the connection open
  sleep "$TIMEOUT"
) | websocat "ws://127.0.0.1:$WEBSOCKET_PORT/" | tee >(cat >"$LOG_FILE") | while IFS= read -r line; do
  # Print each message with timestamp
  echo "[$(date +"%H:%M:%S")] Received: $line"

  # Prettify JSON and append to pretty log file
  echo -e "\n--- Message at $(date +"%H:%M:%S") ---" >>"$PRETTY_LOG"
  echo "$line" | jq '.' >>"$PRETTY_LOG" 2>/dev/null || echo "Invalid JSON: $line" >>"$PRETTY_LOG"

  # Analyze message type
  if echo "$line" | grep -q '"method":'; then
    method=$(echo "$line" | jq -r '.method // "unknown"' 2>/dev/null)
    echo "  → Method: $method"
  fi

  if echo "$line" | grep -q '"id":'; then
    id=$(echo "$line" | jq -r '.id // "unknown"' 2>/dev/null)
    echo "  → ID: $id"

    # If this is a response to our connection message, try sending a test method
    if [ "$id" = "1" ]; then
      echo "Received connection response. Let's try some test methods..."
      sleep 2

      # Test a tool invocation
      send_test_message "tools/call" '{"name":"getCurrentSelection","arguments":{}}' "2"

      # Try another tool invocation
      send_test_message "tools/call" '{"name":"getActiveFilePath","arguments":{}}' "3"

      # Try tools/list method
      send_test_message "tools/list" '{}' "4"

      # Try various method patterns
      send_test_message "listTools" '{}' "5"
      send_test_message "mcp.tools.list" '{}' "6"

      # Try pinging the server
      send_test_message "ping" '{}' "7"
    fi
  fi
done

echo
echo "Listening completed after $TIMEOUT seconds."
echo "Logged all messages to $LOG_FILE"
echo "Prettified messages saved to $PRETTY_LOG"
echo
echo "Message summary:"

# Generate a summary of message methods and IDs
echo "Message methods found:"
grep -o '"method":"[^"]*"' "$LOG_FILE" | sort | uniq -c | sort -nr

echo
echo "Message IDs found:"
grep -o '"id":"[^"]*"' "$LOG_FILE" | sort | uniq -c | sort -nr

# Now analyze the messages that were sent
echo
echo "Analyzing messages..."

# Count number of selection_changed events
selection_changed_count=$(grep -c '"method":"selection_changed"' "$LOG_FILE")
echo "selection_changed notifications: $selection_changed_count"

# Check if we received any tool responses
tool_responses=$(grep -c '"id":"[23]"' "$LOG_FILE")
echo "Tool responses: $tool_responses"

echo
echo "Research complete. See $PRETTY_LOG for detailed message content."
