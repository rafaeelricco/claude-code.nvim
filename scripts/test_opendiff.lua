#!/usr/bin/env lua

-- Test script that mimics Claude Code CLI sending an openDiff tool call
-- This helps automate testing of the openDiff blocking behavior

local socket = require("socket")
local json = require("json") or require("cjson") or require("dkjson")

-- Configuration
local HOST = "127.0.0.1"
local PORT = nil -- Will discover from lock file
local LOCK_FILE_PATH = os.getenv("HOME") .. "/.claude/ide/"

-- Discover port from lock files
local function discover_port()
  local handle = io.popen("ls " .. LOCK_FILE_PATH .. "*.lock 2>/dev/null")
  if not handle then
    print("❌ No lock files found in " .. LOCK_FILE_PATH)
    return nil
  end

  local result = handle:read("*a")
  handle:close()

  if result == "" then
    print("❌ No lock files found")
    return nil
  end

  -- Extract port from first lock file name
  local lock_file = result:match("([^\n]+)")
  local port = lock_file:match("(%d+)%.lock")

  if port then
    print("✅ Discovered port " .. port .. " from " .. lock_file)
    return tonumber(port)
  else
    print("❌ Could not parse port from lock file: " .. lock_file)
    return nil
  end
end

-- Read README.md content
local function read_readme()
  local file = io.open("README.md", "r")
  if not file then
    print("❌ Could not read README.md - run this script from the project root")
    os.exit(1)
  end

  local content = file:read("*a")
  file:close()

  -- Simulate adding a license link (append at end)
  local modified_content = content .. "\n## License\n\n[MIT](LICENSE)\n"

  return content, modified_content
end

-- Create WebSocket handshake
local function websocket_handshake(sock)
  local key = "dGhlIHNhbXBsZSBub25jZQ=="
  local request = string.format(
    "GET / HTTP/1.1\r\n"
      .. "Host: %s:%d\r\n"
      .. "Upgrade: websocket\r\n"
      .. "Connection: Upgrade\r\n"
      .. "Sec-WebSocket-Key: %s\r\n"
      .. "Sec-WebSocket-Version: 13\r\n"
      .. "\r\n",
    HOST,
    PORT,
    key
  )

  sock:send(request)

  local response = sock:receive("*l")
  if not response or not response:match("101 Switching Protocols") then
    print("❌ WebSocket handshake failed")
    return false
  end

  -- Read remaining headers
  repeat
    local line = sock:receive("*l")
  until line == ""

  print("✅ WebSocket handshake successful")
  return true
end

-- Send WebSocket frame
local function send_frame(sock, payload)
  local len = #payload
  local frame = string.char(0x81) -- Text frame, FIN=1

  if len < 126 then
    frame = frame .. string.char(len)
  elseif len < 65536 then
    frame = frame .. string.char(126) .. string.char(math.floor(len / 256)) .. string.char(len % 256)
  else
    error("Payload too large")
  end

  frame = frame .. payload
  sock:send(frame)
end

-- Main test function
local function test_opendiff()
  print("🧪 Starting openDiff automation test...")

  -- Step 1: Discover port
  PORT = discover_port()
  if not PORT then
    print("❌ Make sure Neovim with claudecode.nvim is running first")
    os.exit(1)
  end

  -- Step 2: Read README content
  local old_content, new_content = read_readme()
  print("✅ Loaded README.md (" .. #old_content .. " chars)")

  -- Step 3: Connect to WebSocket
  local sock = socket.tcp()
  sock:settimeout(5)

  local success, err = sock:connect(HOST, PORT)
  if not success then
    print("❌ Could not connect to " .. HOST .. ":" .. PORT .. " - " .. (err or "unknown error"))
    os.exit(1)
  end

  print("✅ Connected to WebSocket server")

  -- Step 4: WebSocket handshake
  if not websocket_handshake(sock) then
    os.exit(1)
  end

  -- Step 5: Send openDiff tool call
  local tool_call = {
    jsonrpc = "2.0",
    id = 1,
    method = "tools/call",
    params = {
      name = "openDiff",
      arguments = {
        old_file_path = os.getenv("PWD") .. "/README.md",
        new_file_path = os.getenv("PWD") .. "/README.md",
        new_file_contents = new_content,
        tab_name = "✻ [Test] README.md (automated) ⧉",
      },
    },
  }

  local json_message = json.encode(tool_call)
  print("📤 Sending openDiff tool call...")
  send_frame(sock, json_message)

  -- Step 6: Wait for response with timeout
  print("⏳ Waiting for response (should block until user interaction)...")
  sock:settimeout(30) -- 30 second timeout

  local response = sock:receive("*l")
  if response then
    print("📥 Received immediate response (BAD - should block):")
    print(response)
  else
    print("✅ No immediate response - tool is properly blocking!")
    print("👉 Now go to Neovim and interact with the diff (save or close)")
    print("👉 Press Ctrl+C here when done testing")

    -- Keep listening for the eventual response
    sock:settimeout(0) -- Non-blocking
    repeat
      local data = sock:receive("*l")
      if data then
        print("📥 Final response received:")
        print(data)
        break
      end
      socket.sleep(0.1)
    until false
  end

  sock:close()
end

-- Check dependencies
if not socket then
  print("❌ luasocket not found. Install with: luarocks install luasocket")
  os.exit(1)
end

if not json then
  print("❌ JSON library not found. Install with: luarocks install dkjson")
  os.exit(1)
end

-- Run the test
test_opendiff()
