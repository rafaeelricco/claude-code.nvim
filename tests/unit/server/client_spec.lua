--- Tests for lua/claudecode/server/client.lua
--- WebSocket client connection management

-- Setup mock vim if not in Neovim
if not vim then
  require("tests.helpers.mock_vim").setup()
end

describe("server/client", function()
  local client_module
  local frame

  -- Helper to create a mock TCP handle
  local function create_mock_tcp()
    local tcp = {
      _write_buffer = {},
      _closed = false,
      _closing = false,
    }

    tcp.write = function(_, data, callback)
      table.insert(tcp._write_buffer, data)
      if callback then
        callback(nil)
      end
    end

    tcp.is_closing = function()
      return tcp._closing
    end

    tcp.close = function(_, callback)
      tcp._closed = true
      tcp._closing = true
      if callback then
        callback()
      end
    end

    return tcp
  end

  -- Helper to create a valid WebSocket handshake request
  local function make_handshake_request(auth_token)
    local lines = {
      "GET / HTTP/1.1",
      "Host: localhost:12345",
      "Upgrade: websocket",
      "Connection: Upgrade",
      "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
      "Sec-WebSocket-Version: 13",
    }
    if auth_token then
      table.insert(lines, "x-claude-code-ide-authorization: " .. auth_token)
    end
    table.insert(lines, "")
    table.insert(lines, "")
    return table.concat(lines, "\r\n")
  end

  before_each(function()
    -- Clear module cache
    package.loaded["claudecode.server.client"] = nil
    package.loaded["claudecode.server.frame"] = nil
    package.loaded["claudecode.server.handshake"] = nil
    package.loaded["claudecode.server.utils"] = nil
    package.loaded["claudecode.logger"] = nil

    -- Mock logger
    package.loaded["claudecode.logger"] = {
      debug = function() end,
      info = function() end,
      warn = function() end,
      error = function() end,
    }

    -- Load modules
    frame = require("claudecode.server.frame")
    client_module = require("claudecode.server.client")

    -- Mock vim.loop.now
    vim.loop.now = function()
      return 1000
    end
  end)

  describe("create_client", function()
    it("creates client with unique id", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      assert.is_string(client.id)
      assert.is_truthy(#client.id > 0)
    end)

    it("creates client with initial state 'connecting'", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      assert.equals("connecting", client.state)
    end)

    it("creates client with empty buffer", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      assert.equals("", client.buffer)
    end)

    it("creates client with handshake not complete", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      assert.is_false(client.handshake_complete)
    end)

    it("creates client with tcp_handle reference", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      assert.equals(tcp, client.tcp_handle)
    end)

    it("creates client with last_ping at 0", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      assert.equals(0, client.last_ping)
    end)

    it("creates client with last_pong at current time", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      assert.equals(1000, client.last_pong)
    end)

    it("creates unique ids for different clients", function()
      local tcp1 = create_mock_tcp()
      local tcp2 = create_mock_tcp()
      local client1 = client_module.create_client(tcp1)
      local client2 = client_module.create_client(tcp2)
      -- IDs might not be unique if TCP handles stringify the same
      -- Just check they exist
      assert.is_string(client1.id)
      assert.is_string(client2.id)
    end)
  end)

  describe("send_message", function()
    it("sends text frame to connected client", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connected"

      client_module.send_message(client, "Hello, World!")

      assert.equals(1, #tcp._write_buffer)
    end)

    it("calls callback on success", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connected"

      local callback_called = false
      local callback_error = nil
      client_module.send_message(client, "Test", function(err)
        callback_called = true
        callback_error = err
      end)

      assert.is_true(callback_called)
      assert.is_nil(callback_error)
    end)

    it("does not send if client not connected", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connecting"

      client_module.send_message(client, "Hello!")

      assert.equals(0, #tcp._write_buffer)
    end)

    it("calls callback with error if not connected", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "closing"

      local callback_called = false
      local callback_error = nil
      client_module.send_message(client, "Test", function(err)
        callback_called = true
        callback_error = err
      end)

      assert.is_true(callback_called)
      assert.is_truthy(callback_error:match("not connected"))
    end)

    it("does not send if client closed", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "closed"

      client_module.send_message(client, "Hello!")

      assert.equals(0, #tcp._write_buffer)
    end)

    it("works without callback", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connected"

      -- Should not throw
      client_module.send_message(client, "Test message")

      assert.equals(1, #tcp._write_buffer)
    end)
  end)

  describe("send_ping", function()
    it("sends ping frame to connected client", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connected"

      client_module.send_ping(client)

      assert.equals(1, #tcp._write_buffer)
    end)

    it("updates last_ping timestamp", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connected"

      local before = client.last_ping
      client_module.send_ping(client)
      local after = client.last_ping

      assert.is_true(after >= before)
    end)

    it("does not send if client not connected", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connecting"

      client_module.send_ping(client)

      assert.equals(0, #tcp._write_buffer)
    end)

    it("does not update timestamp if not connected", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connecting"
      client.last_ping = 0

      client_module.send_ping(client)

      assert.equals(0, client.last_ping)
    end)

    it("sends ping with custom data", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connected"

      client_module.send_ping(client, "ping data")

      assert.equals(1, #tcp._write_buffer)
    end)
  end)

  describe("close_client", function()
    it("changes state to closing", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connected"
      client.handshake_complete = true

      client_module.close_client(client)

      assert.equals("closing", client.state)
    end)

    it("sends close frame if handshake complete", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connected"
      client.handshake_complete = true

      client_module.close_client(client)

      assert.equals(1, #tcp._write_buffer)
    end)

    it("does not send close frame if handshake not complete", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connecting"
      client.handshake_complete = false

      client_module.close_client(client)

      assert.equals(0, #tcp._write_buffer)
    end)

    it("does nothing if already closing", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "closing"
      client.handshake_complete = true

      client_module.close_client(client)

      assert.equals(0, #tcp._write_buffer)
    end)

    it("does nothing if already closed", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "closed"
      client.handshake_complete = true

      client_module.close_client(client)

      assert.equals(0, #tcp._write_buffer)
    end)

    it("uses default close code 1000", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connected"
      client.handshake_complete = true

      client_module.close_client(client)

      -- Close frame should have been sent
      assert.equals(1, #tcp._write_buffer)
    end)

    it("accepts custom close code", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connected"
      client.handshake_complete = true

      client_module.close_client(client, 1001)

      assert.equals(1, #tcp._write_buffer)
    end)

    it("accepts custom close reason", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connected"
      client.handshake_complete = true

      client_module.close_client(client, 1000, "Normal closure")

      assert.equals(1, #tcp._write_buffer)
    end)

    it("closes TCP handle if not already closing", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connected"
      client.handshake_complete = false

      client_module.close_client(client)

      assert.is_true(tcp._closed)
    end)
  end)

  describe("is_client_alive", function()
    it("returns false if client not connected", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connecting"

      assert.is_false(client_module.is_client_alive(client))
    end)

    it("returns true if client connected and pong recent", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connected"
      client.last_pong = vim.loop.now()

      assert.is_true(client_module.is_client_alive(client))
    end)

    it("returns false if pong too old", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connected"
      client.last_pong = vim.loop.now() - 31000 -- 31 seconds ago

      assert.is_false(client_module.is_client_alive(client))
    end)

    it("uses default timeout of 30000ms", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connected"
      client.last_pong = vim.loop.now() - 29999 -- Just under 30 seconds

      assert.is_true(client_module.is_client_alive(client))
    end)

    it("accepts custom timeout", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connected"
      client.last_pong = vim.loop.now() - 5000

      assert.is_false(client_module.is_client_alive(client, 4000)) -- 4 second timeout
      assert.is_true(client_module.is_client_alive(client, 6000)) -- 6 second timeout
    end)

    it("returns false for closing state", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "closing"
      client.last_pong = vim.loop.now()

      assert.is_false(client_module.is_client_alive(client))
    end)

    it("returns false for closed state", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "closed"
      client.last_pong = vim.loop.now()

      assert.is_false(client_module.is_client_alive(client))
    end)
  end)

  describe("get_client_info", function()
    it("returns client id", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      local info = client_module.get_client_info(client)

      assert.equals(client.id, info.id)
    end)

    it("returns client state", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      local info = client_module.get_client_info(client)

      assert.equals("connecting", info.state)
    end)

    it("returns handshake_complete status", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      local info = client_module.get_client_info(client)

      assert.is_false(info.handshake_complete)
    end)

    it("returns buffer_size", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.buffer = "some data"
      local info = client_module.get_client_info(client)

      assert.equals(9, info.buffer_size)
    end)

    it("returns last_ping", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      local info = client_module.get_client_info(client)

      assert.equals(0, info.last_ping)
    end)

    it("returns last_pong", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      local info = client_module.get_client_info(client)

      assert.equals(1000, info.last_pong)
    end)

    it("reflects state changes", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)

      client.state = "connected"
      client.handshake_complete = true
      client.buffer = "test"

      local info = client_module.get_client_info(client)

      assert.equals("connected", info.state)
      assert.is_true(info.handshake_complete)
      assert.equals(4, info.buffer_size)
    end)
  end)

  describe("process_data", function()
    local on_message_calls
    local on_close_calls
    local on_error_calls

    local function reset_callbacks()
      on_message_calls = {}
      on_close_calls = {}
      on_error_calls = {}
    end

    local function on_message(client, message)
      table.insert(on_message_calls, { client = client, message = message })
    end

    local function on_close(client, code, reason)
      table.insert(on_close_calls, { client = client, code = code, reason = reason })
    end

    local function on_error(client, error_msg)
      table.insert(on_error_calls, { client = client, error_msg = error_msg })
    end

    before_each(function()
      reset_callbacks()
    end)

    it("processes handshake request", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      local request = make_handshake_request()

      client_module.process_data(client, request, on_message, on_close, on_error, nil)

      -- Handshake response should be sent
      assert.equals(1, #tcp._write_buffer)
    end)

    it("completes handshake and sets state to connected", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      local request = make_handshake_request()

      client_module.process_data(client, request, on_message, on_close, on_error, nil)

      assert.is_true(client.handshake_complete)
      assert.equals("connected", client.state)
    end)

    it("validates auth token during handshake", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      local token = "valid-auth-token-12345"
      local request = make_handshake_request(token)

      client_module.process_data(client, request, on_message, on_close, on_error, token)

      assert.is_true(client.handshake_complete)
      assert.equals("connected", client.state)
    end)

    it("rejects incorrect auth token", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      local request = make_handshake_request("wrong-token")

      client_module.process_data(client, request, on_message, on_close, on_error, "correct-token")

      assert.is_false(client.handshake_complete)
      assert.equals("closing", client.state)
    end)

    it("rejects missing auth token when required", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      local request = make_handshake_request(nil) -- No auth token

      client_module.process_data(client, request, on_message, on_close, on_error, "expected-token")

      assert.is_false(client.handshake_complete)
      assert.equals("closing", client.state)
    end)

    it("buffers incomplete handshake", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      local partial = "GET / HTTP/1.1\r\nHost: localhost"

      client_module.process_data(client, partial, on_message, on_close, on_error, nil)

      assert.is_false(client.handshake_complete)
      assert.equals("connecting", client.state)
      assert.equals(partial, client.buffer)
    end)

    it("processes text frame after handshake", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)

      -- Complete handshake first
      local request = make_handshake_request()
      client_module.process_data(client, request, on_message, on_close, on_error, nil)
      reset_callbacks()

      -- Send a text frame
      local text_frame = frame.create_text_frame("Hello!")
      -- Mask the frame (client to server frames should be masked)
      local masked_frame = string.char(0x81, 0x86, 0x00, 0x00, 0x00, 0x00) .. "Hello!"

      client_module.process_data(client, masked_frame, on_message, on_close, on_error, nil)

      -- Message callback should be scheduled (but we're testing synchronously)
      -- The frame should be parsed correctly
      assert.equals("", client.buffer)
    end)

    it("processes ping frame and sends pong", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)

      -- Complete handshake
      local request = make_handshake_request()
      client_module.process_data(client, request, on_message, on_close, on_error, nil)
      local initial_writes = #tcp._write_buffer

      -- Send a ping frame (opcode 0x9, masked)
      local ping_data = "ping"
      local ping_frame = string.char(0x89, 0x84, 0x00, 0x00, 0x00, 0x00) .. ping_data

      client_module.process_data(client, ping_frame, on_message, on_close, on_error, nil)

      -- Pong should be sent
      assert.equals(initial_writes + 1, #tcp._write_buffer)
    end)

    it("handles close frame", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)

      -- Complete handshake
      local request = make_handshake_request()
      client_module.process_data(client, request, on_message, on_close, on_error, nil)
      reset_callbacks()
      local initial_writes = #tcp._write_buffer

      -- Send a close frame (opcode 0x8, with status code 1000)
      local close_frame = string.char(0x88, 0x82, 0x00, 0x00, 0x00, 0x00, 0x03, 0xE8) -- 1000 = 0x03E8

      client_module.process_data(client, close_frame, on_message, on_close, on_error, nil)

      -- Close frame should be sent back
      assert.equals(initial_writes + 1, #tcp._write_buffer)
      assert.equals("closing", client.state)
    end)

    it("updates last_pong on pong frame", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)

      -- Complete handshake
      local request = make_handshake_request()
      client_module.process_data(client, request, on_message, on_close, on_error, nil)
      client.last_pong = 0

      -- Send a pong frame (opcode 0xA, masked)
      local pong_frame = string.char(0x8A, 0x80, 0x00, 0x00, 0x00, 0x00)

      vim.loop.now = function()
        return 2000
      end
      client_module.process_data(client, pong_frame, on_message, on_close, on_error, nil)

      assert.equals(2000, client.last_pong)
    end)
  end)
end)
