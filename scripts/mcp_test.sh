#!/usr/bin/env bash

# mcp_test.sh - Consolidated test script for Claude Code WebSocket MCP protocol
# This script tests various aspects of the MCP protocol implementation.
#
# IMPORTANT: All JSON must be single-line for WebSocket JSON-RPC to work properly.
# When adding or modifying JSON parameters, always use ws_format_json to ensure proper formatting.

set -e

CLAUDE_LIB_DIR="$(dirname "$(realpath "$0")")"

source "$CLAUDE_LIB_DIR/lib_claude.sh"
source "$CLAUDE_LIB_DIR/lib_ws_persistent.sh"

# Configuration
TIMEOUT=5               # Seconds to wait for each response
LOG_DIR="mcp_test_logs" # Directory for log files
# No default log file needed - each test creates its own log files
WEBSOCKET_PORT=""  # Will be detected automatically
WAIT_BETWEEN=1     # Seconds to wait between test requests
CONN_ID="mcp_test" # WebSocket connection ID

# Parse command line arguments
usage() {
  echo "Usage: $0 [options] [test1,test2,...]"
  echo
  echo "Options:"
  echo "  -p, --port PORT     Specify WebSocket port (otherwise auto-detected)"
  echo "  -l, --logs DIR      Specify log directory (default: $LOG_DIR)"
  echo "  -t, --timeout SEC   Specify timeout in seconds (default: $TIMEOUT)"
  echo "  -c, --compact       Use compact display for tools list (name and type only)"
  echo "  -h, --help          Show this help message"
  echo
  echo "Available tests:"
  echo "  all                 Run all tests (default)"
  echo "  connect             Test basic connection"
  echo "  toolslist           Test tools/list method"
  echo "  toolinvoke          Test tool invocation"
  echo "  methods             Test various method patterns"
  echo "  selection           Test selection notifications"
  echo
  echo "Example: $0 toolslist,connect"
  echo
  exit 1
}

TESTS_TO_RUN=()
COMPACT_VIEW=false

while [[ $# -gt 0 ]]; do
  case $1 in
  -p | --port)
    WEBSOCKET_PORT="$2"
    shift 2
    ;;
  -l | --logs)
    LOG_DIR="$2"
    shift 2
    ;;
  -t | --timeout)
    TIMEOUT="$2"
    shift 2
    ;;
  -c | --compact)
    COMPACT_VIEW=true
    shift
    ;;
  -h | --help)
    usage
    ;;
  *)
    # Parse comma-separated list of tests
    IFS=',' read -ra TESTS <<<"$1"
    for test in "${TESTS[@]}"; do
      TESTS_TO_RUN+=("$test")
    done
    shift
    ;;
  esac
done

# If no tests specified, run all
if [ ${#TESTS_TO_RUN[@]} -eq 0 ]; then
  TESTS_TO_RUN=("all")
fi

mkdir -p "$LOG_DIR"

# Get WebSocket port if not provided
if [ -z "$WEBSOCKET_PORT" ]; then
  WEBSOCKET_PORT=$(find_claude_lockfile)
fi

echo "Using WebSocket port: $WEBSOCKET_PORT"
echo "Logs will be stored in: $LOG_DIR"
echo

############################################################
# Test Functions
############################################################

# Callback function to handle selection_changed notifications
handle_selection_changed() {
  local message="$1"
  local count="$2"
  echo "📝 Received selection_changed notification #$count (this is normal and will be ignored)"
}

# Test function for basic connection
test_connection() {
  local log_file="$LOG_DIR/connection_test.jsonl"
  local pretty_log="$LOG_DIR/connection_test_pretty.txt"

  echo "=== Running Connection Test ==="
  echo "Logs: $log_file"
  echo

  # Clear previous log files
  true >"$log_file"
  true >"$pretty_log"

  # Create WebSocket URL
  local ws_url="ws://127.0.0.1:$WEBSOCKET_PORT/"

  echo "Connecting to WebSocket server at $ws_url"

  # Establish persistent connection
  if ! ws_connect "$ws_url" "$CONN_ID"; then
    echo "❌ Failed to connect to WebSocket server"
    return 1
  fi

  # Start a listener for selection_changed notifications
  ws_start_listener "$CONN_ID" handle_selection_changed "selection_changed"

  # Initialize connection with proper MCP lifecycle - must be single line
  local init_params
  init_params=$(ws_format_json '{"protocolVersion":"2025-03-26","capabilities":{"roots":{"listChanged":true},"sampling":{}},"clientInfo":{"name":"mcp-test-client","version":"1.0.0"}}')

  echo "Sending initialize request..."
  echo

  # Send initialize message and capture response
  local response
  response=$(ws_rpc_request "initialize" "$init_params" "connect-test" "$CONN_ID" "$TIMEOUT")

  # Send initialized notification after getting the response
  echo "Sending initialized notification..."
  ws_notify "notifications/initialized" "{}" "$CONN_ID"

  # Log the request and response
  local request
  request=$(ws_create_message "initialize" "$init_params" "connect-test")

  # Combine multiple redirects to the same files
  {
    echo "$request"
    echo "$response"
  } >>"$log_file"

  # Log with proper formatting
  {
    echo -e "\n--- Initialize Request ---"
    echo "$request" | jq '.'
    echo -e "\n--- Initialize Response ---"
    echo "$response" | jq '.' 2>/dev/null || echo "Invalid JSON: $response"

    # Log the initialized notification
    local init_notification
    init_notification=$(ws_create_message "notifications/initialized" "{}" "")
    echo -e "\n--- Initialized Notification ---"
    echo "$init_notification" | jq '.'
  } >>"$pretty_log"

  # Display and analyze the response
  echo "Response:"
  echo "$response"
  echo

  if echo "$response" | grep -q '"id":"connect-test"'; then
    echo "✅ Received response to our initialize request!"

    # Extract server info if present
    local server_info
    server_info=$(echo "$response" | jq -r '.result.serverInfo // "Not provided"' 2>/dev/null)
    local protocol
    protocol=$(echo "$response" | jq -r '.result.protocolVersion // "Not provided"' 2>/dev/null)

    # Extract server capabilities
    local capabilities
    capabilities=$(echo "$response" | jq -r '.result.capabilities // "None"' 2>/dev/null)

    echo "Server info: $server_info"
    echo "Protocol version: $protocol"
    echo "Server capabilities: $capabilities"
  else
    echo "⚠️ No direct response to our initialize request"

    if echo "$response" | grep -q '"method":"selection_changed"'; then
      echo "📝 Received a selection_changed notification instead (this is normal for VSCode extension)"
    fi
  fi

  echo "=== Connection Test Completed ==="
  echo
}

# Test function for tools/list method
test_tools_list() {
  local log_file="$LOG_DIR/tools_list_test.jsonl"
  local pretty_log="$LOG_DIR/tools_list_test_pretty.txt"

  echo "=== Running Tools List Test ==="
  echo "Logs: $log_file"
  echo

  # Clear previous log files
  true >"$log_file"
  true >"$pretty_log"

  # Make sure we're using an existing connection
  if ! ws_is_connected "$CONN_ID"; then
    echo "⚠️ WebSocket connection not active. Establishing connection..."
    local ws_url="ws://127.0.0.1:$WEBSOCKET_PORT/"
    if ! ws_connect "$ws_url" "$CONN_ID"; then
      echo "❌ Failed to connect to WebSocket server"
      return 1
    fi

    # Start a listener for selection_changed notifications
    ws_start_listener "$CONN_ID" handle_selection_changed "selection_changed"
  fi

  echo "Sending tools/list request..."
  echo

  # Send request and capture response
  local params
  params=$(ws_format_json '{}')
  local response
  response=$(ws_rpc_request "tools/list" "$params" "tools-list-test" "$CONN_ID" "$TIMEOUT")

  # Create the full request for logging
  local request
  request=$(ws_create_message "tools/list" "$params" "tools-list-test")

  # Log the request and response
  echo "$request" >>"$log_file"
  echo "$response" >>"$log_file"
  {
    echo -e "\n--- Tools List Request ---"
    echo "$request" | jq '.'
    echo -e "\n--- Tools List Response ---"
    echo "$response" | jq '.' 2>/dev/null || echo "Invalid JSON: $response"
  } >>"$pretty_log"

  # Display and analyze the response
  echo "Response received."

  if echo "$response" | grep -q '"error"'; then
    local error_code
    error_code=$(echo "$response" | jq -r '.error.code // "unknown"' 2>/dev/null)
    local error_message
    error_message=$(echo "$response" | jq -r '.error.message // "unknown"' 2>/dev/null)
    echo "❌ Error response: Code $error_code - $error_message"
  elif echo "$response" | grep -q '"result"'; then
    echo "✅ Successful response with tools list!"

    # Extract and count tools
    local tools_count
    tools_count=$(echo "$response" | jq '.result.tools | length' 2>/dev/null)
    echo "Found $tools_count tools in the response."

    # Format and display tools
    if [ "$COMPACT_VIEW" = "true" ]; then
      # Compact view - just name, type and required parameters
      echo "Tools (compact view):"
      # Using a safer approach for the compact view
      # Process each tool individually
      echo "$response" | jq -r '.result.tools[] | .name' | while read -r name; do
        # Output tool name
        echo "  - $name"

        # Get tool schema
        schema=$(echo "$response" | jq -r --arg name "$name" '.result.tools[] | select(.name == $name) | .inputSchema // {}')
        has_props=$(echo "$schema" | jq 'has("properties")')

        if [ "$has_props" = "true" ]; then
          echo "    Parameters:"

          # Get the keys and required list
          required_list=$(echo "$schema" | jq -r '.required // []')
          keys=$(echo "$schema" | jq -r '.properties | keys[]')

          for key in $keys; do
            # Get the type
            type=$(echo "$schema" | jq -r --arg key "$key" '.properties[$key].type // "any"')

            # Check if required
            is_required=""
            if echo "$required_list" | jq -r 'contains(["'"$key"'"])' | grep -q "true"; then
              is_required=" [REQUIRED]"
            fi

            # Output parameter
            echo "      - $key ($type)$is_required"
          done
        else
          echo "    Parameters: None"
        fi
      done
    else
      # Detailed view
      # Create helper function to format tool details
      format_tool_details() {
        local tool=$1
        local name
        name=$(echo "$tool" | jq -r '.name')
        local desc
        desc=$(echo "$tool" | jq -r '.description // ""')

        # Print tool name and description (truncated if too long)
        echo "  - $name"
        if [ -n "$desc" ]; then
          # Truncate description if longer than 70 chars
          if [ ${#desc} -gt 70 ]; then
            echo "    Description: ${desc:0:67}..."
          else
            echo "    Description: $desc"
          fi
        fi

        # Get parameters - look for inputSchema which is where parameters actually are
        local schema
        schema=$(echo "$tool" | jq -r '.inputSchema // {}')
        local has_props
        has_props=$(echo "$schema" | jq 'has("properties")')

        if [ "$has_props" = "true" ]; then
          echo "    Parameters:"

          # Get required fields
          local required_fields
          required_fields=$(echo "$schema" | jq -r '.required // []')

          # Process each property - get keys first, then look up each property
          local keys
          keys=$(echo "$schema" | jq -r '.properties | keys[]')

          for key in $keys; do

            # Declare variables separately to avoid masking return values
            local type
            type=$(echo "$schema" | jq -r ".properties[\"$key\"].type // \"any\"")

            local param_desc
            param_desc=$(echo "$schema" | jq -r ".properties[\"$key\"].description // \"\"")

            # Check if required
            local is_required=""
            if echo "$required_fields" | jq -r 'contains(["'"$key"'"])' | grep -q "true"; then
              is_required=" [REQUIRED]"
            fi

            # Format parameter information
            echo "      - $key ($type)$is_required"
            if [ -n "$param_desc" ]; then
              # Truncate description if longer than 60 chars
              if [ ${#param_desc} -gt 60 ]; then
                echo "        Description: ${param_desc:0:57}..."
              else
                echo "        Description: $param_desc"
              fi
            fi
          done # end of for key loop
        else
          echo "    Parameters: None"
        fi
        echo
      }

      # Format and display tools
      echo "Tools and their parameters (detailed view):"
      echo "$response" | jq -r '.result.tools[] | @json' | while read -r tool; do
        format_tool_details "$tool"
      done
    fi
  elif echo "$response" | grep -q '"method":"selection_changed"'; then
    echo "⚠️ Received selection_changed notification instead of response"
  else
    echo "⚠️ Unexpected response format"
  fi

  echo "=== Tools List Test Completed ==="
  echo
  echo "For full details, see: $pretty_log"
  echo
}

# Test function for tool invocation
test_tool_invoke() {
  local log_file="$LOG_DIR/tool_invoke_test.jsonl"
  local pretty_log="$LOG_DIR/tool_invoke_test_pretty.txt"

  echo "=== Running Tool Invocation Test ==="
  echo "Logs: $log_file"
  echo

  # Clear previous log files
  true >"$log_file"
  true >"$pretty_log"

  # Make sure we're using an existing connection
  if ! ws_is_connected "$CONN_ID"; then
    echo "⚠️ WebSocket connection not active. Establishing connection..."
    local ws_url="ws://127.0.0.1:$WEBSOCKET_PORT/"
    if ! ws_connect "$ws_url" "$CONN_ID"; then
      echo "❌ Failed to connect to WebSocket server"
      return 1
    fi

    # Start a listener for selection_changed notifications
    ws_start_listener "$CONN_ID" handle_selection_changed "selection_changed"
  fi

  # Define test cases for tool invocation
  local test_cases=(
    # Format: "method params id"
    # Note: params need to be properly escaped for shell parsing but will be formatted with ws_format_json
    "tools/call '{\"name\":\"getCurrentSelection\",\"arguments\":{}}' tools-call-1"
    "tools/call '{\"name\":\"getWorkspaceFolders\",\"arguments\":{}}' tools-call-2"
    "tools/list '{}' direct-2"
  )

  echo "Testing tool invocations with various formats..."
  echo

  for test_case in "${test_cases[@]}"; do
    read -r method params id <<<"$test_case"

    echo "=== Testing: $method (ID: $id) ==="

    # Format params
    params=$(ws_format_json "$params")

    # Send request and capture response
    local response
    response=$(ws_rpc_request "$method" "$params" "$id" "$CONN_ID" "$TIMEOUT")

    # Create full request for logging
    local request
    request=$(ws_create_message "$method" "$params" "$id")
    echo "Request: $request"

    # Log the request and response
    echo "$request" >>"$log_file"
    echo "$response" >>"$log_file"
    {
      echo -e "\n--- Tool Invoke Request: $method (ID: $id) ---"
      echo "$request" | jq '.'
      echo -e "\n--- Tool Invoke Response: $method (ID: $id) ---"
      echo "$response" | jq '.' 2>/dev/null || echo "Invalid JSON: $response"
    } >>"$pretty_log"

    # Display and analyze the response
    if echo "$response" | grep -q '"error"'; then
      local error_code
      error_code=$(echo "$response" | jq -r '.error.code // "unknown"' 2>/dev/null)
      local error_message
      error_message=$(echo "$response" | jq -r '.error.message // "unknown"' 2>/dev/null)
      echo "❌ Error response: Code $error_code - $error_message"
    elif echo "$response" | grep -q '"result"'; then
      echo "✅ Successful response with result"
    elif echo "$response" | grep -q '"method":"selection_changed"'; then
      echo "⚠️ Received selection_changed notification instead of response"
    else
      echo "⚠️ Unexpected response format"
    fi

    echo "=== End Testing: $method ==="
    echo

    # Wait a bit before the next request
    sleep $WAIT_BETWEEN
  done

  echo "=== Tool Invocation Test Completed ==="
  echo
  echo "For full details, see: $pretty_log"
  echo
}

# Test function for method patterns
test_methods() {
  local log_file="$LOG_DIR/methods_test.jsonl"
  local pretty_log="$LOG_DIR/methods_test_pretty.txt"

  echo "=== Running Method Patterns Test ==="
  echo "Logs: $log_file"
  echo

  # Clear previous log files
  true >"$log_file"
  true >"$pretty_log"

  # Make sure we're using an existing connection
  if ! ws_is_connected "$CONN_ID"; then
    echo "⚠️ WebSocket connection not active. Establishing connection..."
    local ws_url="ws://127.0.0.1:$WEBSOCKET_PORT/"
    if ! ws_connect "$ws_url" "$CONN_ID"; then
      echo "❌ Failed to connect to WebSocket server"
      return 1
    fi

    # Start a listener for selection_changed notifications
    ws_start_listener "$CONN_ID" handle_selection_changed "selection_changed"
  fi

  # Define test cases for different method patterns
  local test_cases=(
    # Format: "method params id description"
    # Note: params will be formatted with ws_format_json
    "tools/list '{}' methods-1 'Standard tools/list method'"
    "mcp.tools.list '{}' methods-2 'MCP prefix style'"
    "$/tools.list '{}' methods-3 'JSON-RPC style'"
    "listTools '{}' methods-4 'Direct method name'"
  )

  echo "Testing various method patterns..."
  echo

  for test_case in "${test_cases[@]}"; do
    # Parse the test case
    read -r method params id description <<<"$test_case"

    echo "=== Testing method: $method ($description) ==="

    # Format params properly
    params=$(ws_format_json "$params")

    # Send request and capture response using our persistent connection
    local response
    response=$(ws_rpc_request "$method" "$params" "$id" "$CONN_ID" "$TIMEOUT")

    # Create full request for logging
    local request
    request=$(ws_create_message "$method" "$params" "$id")
    echo "Request: $request"

    # Log the request and response
    echo "$request" >>"$log_file"
    echo "$response" >>"$log_file"
    {
      echo -e "\n--- Method Request: $method (ID: $id) ---"
      echo "$request" | jq '.' 2>/dev/null
      echo -e "\n--- Method Response: $method (ID: $id) ---"
      echo "$response" | jq '.' 2>/dev/null || echo "Invalid JSON: $response"
    } >>"$pretty_log"

    # Display and analyze the response
    if echo "$response" | grep -q '"error"'; then
      local error_code
      error_code=$(echo "$response" | jq -r '.error.code // "unknown"' 2>/dev/null)
      local error_message
      error_message=$(echo "$response" | jq -r '.error.message // "unknown"' 2>/dev/null)
      echo "❌ Error response: Code $error_code - $error_message"
    elif echo "$response" | grep -q '"result"'; then
      echo "✅ Successful response with result"
    elif echo "$response" | grep -q '"method":"selection_changed"'; then
      echo "⚠️ Received selection_changed notification instead of response"
    else
      echo "⚠️ Unexpected response format"
    fi

    echo "=== End Testing: $method ==="
    echo

    # Wait a bit before the next request
    sleep $WAIT_BETWEEN
  done

  echo "=== Method Patterns Test Completed ==="
  echo
  echo "For full details, see: $pretty_log"
  echo
}

# Selection notification handler for listener
handle_selection_test() {
  local message="$1"
  local count="$2"
  local log_file="$3"
  local pretty_log="$4"

  echo "📝 Received selection_changed notification #$count"

  # Extract some details
  local is_empty
  is_empty=$(echo "$message" | jq -r '.params.selection.isEmpty // "unknown"' 2>/dev/null)
  local file_path
  file_path=$(echo "$message" | jq -r '.params.filePath // "unknown"' 2>/dev/null)
  local text_length
  text_length=$(echo "$message" | jq -r '.params.text | length // 0' 2>/dev/null)

  echo "  File: $file_path"
  echo "  Empty selection: $is_empty"
  echo "  Text length: $text_length characters"
  echo

  # Log to the files
  echo "$message" >>"$log_file"
  echo -e "\n--- Selection Changed Notification #$count ---" >>"$pretty_log"
  echo "$message" | jq '.' >>"$pretty_log" 2>/dev/null || echo "Invalid JSON: $message" >>"$pretty_log"
}

# Test function for selection notifications
test_selection() {
  local log_file="$LOG_DIR/selection_test.jsonl"
  local pretty_log="$LOG_DIR/selection_test_pretty.txt"
  local listen_duration=10 # seconds to listen for selection events

  echo "=== Running Selection Notification Test ==="
  echo "Logs: $log_file"
  echo

  # Clear previous log files
  true >"$log_file"
  true >"$pretty_log"

  # Make sure we have a fresh connection for selection test
  local ws_url="ws://127.0.0.1:$WEBSOCKET_PORT/"

  # Clean up any existing connection
  if ws_is_connected "$CONN_ID"; then
    echo "Disconnecting existing WebSocket connection..."
    ws_disconnect "$CONN_ID"
  fi

  echo "Establishing connection to WebSocket server at $ws_url"
  if ! ws_connect "$ws_url" "$CONN_ID"; then
    echo "❌ Failed to connect to WebSocket server"
    return 1
  fi

  echo "Listening for selection_changed events for $listen_duration seconds..."
  echo "Please make some selections in your editor during this time."
  echo

  # Set up selection_changed listener - we need a wrapper for the callback to include the log files
  selection_callback() {
    local message="$1"
    local count="$2"
    handle_selection_test "$message" "$count" "$log_file" "$pretty_log"
  }

  # Start the listener
  ws_start_listener "$CONN_ID" selection_callback "selection_changed"

  # Initialize connection with proper MCP lifecycle - must be single line
  local init_params
  init_params=$(ws_format_json '{"protocolVersion":"2025-03-26","capabilities":{"roots":{"listChanged":true},"sampling":{}},"clientInfo":{"name":"mcp-test-client","version":"1.0.0"}}')

  # Send initialize request
  ws_rpc_request "initialize" "$init_params" "selection-test" "$CONN_ID" "$TIMEOUT" >/dev/null

  # Send initialized notification
  ws_notify "notifications/initialized" "{}" "$CONN_ID"

  echo "Connection established. Waiting for $listen_duration seconds to collect selection events..."

  # Wait for the specified duration
  local start_time
  start_time=$(date +%s)
  local end_time=$((start_time + listen_duration))

  # Display a countdown
  while [[ $(date +%s) -lt $end_time ]]; do
    local remaining=$((end_time - $(date +%s)))
    echo -ne "Collecting events: $remaining seconds remaining...\r"
    sleep 1
  done
  echo -e "\nTime's up!"

  # Stop the listener
  ws_stop_listener "$CONN_ID"

  # Count recorded notifications from the log file
  local selection_count
  selection_count=$(grep -c '"method":"selection_changed"' "$log_file")

  echo "Received $selection_count selection_changed notifications."
  echo "=== Selection Notification Test Completed ==="
  echo
  echo "For full details, see: $pretty_log"
  echo
}

############################################################
# Main execution
############################################################

# Run tests based on user input
should_run_test() {
  local test="$1"

  # If "all" is in the list, run all tests
  for t in "${TESTS_TO_RUN[@]}"; do
    if [[ $t == "all" ]]; then
      return 0
    fi
  done

  # Check if the specific test is in the list
  for t in "${TESTS_TO_RUN[@]}"; do
    if [[ $t == "$test" ]]; then
      return 0
    fi
  done

  return 1
}

# Run the specified tests
if should_run_test "connect"; then
  test_connection
fi

if should_run_test "toolslist"; then
  test_tools_list
fi

if should_run_test "toolinvoke"; then
  test_tool_invoke
fi

if should_run_test "methods"; then
  test_methods
fi

if should_run_test "selection"; then
  test_selection
fi

# Clean up WebSocket connections
if ws_is_connected "$CONN_ID"; then
  echo "Cleaning up WebSocket connection..."
  ws_disconnect "$CONN_ID"
fi

echo "All requested tests completed."
echo "Log files are available in: $LOG_DIR"
