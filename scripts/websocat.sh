#!/usr/bin/env bash

CLAUDE_LIB_DIR="$(dirname "$(realpath "$0")")"

# shellcheck source=./lib_claude.sh
source "$CLAUDE_LIB_DIR/lib_claude.sh"

websocat "$(get_claude_ws_url)"

# Tools list
# { "jsonrpc": "2.0", "id": "tools-list-test", "method": "tools/list", "params": {} }
#
# {"jsonrpc":"2.0","id":"direct-1","method":"getCurrentSelection","params":{}}
#
# { "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": { "name": "getCurrentSelection", "arguments": { } } }
