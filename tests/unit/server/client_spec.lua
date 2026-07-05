--- Tests for lua/claudecode/server/client.lua

if not vim then
  require("tests.helpers.mock_vim").setup()
end

describe("server/client", function()
  local client_module

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
    package.loaded["claudecode.server.client"] = nil
    package.loaded["claudecode.server.frame"] = nil
    package.loaded["claudecode.server.handshake"] = nil
    package.loaded["claudecode.server.utils"] = nil
    package.loaded["claudecode.logger"] = {
      debug = function() end,
      info = function() end,
      warn = function() end,
      error = function() end,
    }

    vim.loop.now = function()
      return 1000
    end

    client_module = require("claudecode.server.client")
  end)

  describe("client lifecycle", function()
    it("starts in connecting state with a live pong timestamp", function()
      local client = client_module.create_client(create_mock_tcp())

      assert.is_string(client.id)
      assert.equals("connecting", client.state)
      assert.is_false(client.handshake_complete)
      assert.equals(1000, client.last_pong)
    end)

    it("sends only when connected", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client_module.send_message(client, "blocked")
      assert.equals(0, #tcp._write_buffer)

      client.state = "connected"
      client_module.send_message(client, "ok")
      assert.equals(1, #tcp._write_buffer)
    end)

    it("closes with a close frame after handshake", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client.state = "connected"
      client.handshake_complete = true

      client_module.close_client(client)

      assert.equals("closed", client.state)
      assert.equals(1, #tcp._write_buffer)
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

    it("completes handshake and writes response", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)

      client_module.process_data(client, make_handshake_request(), on_message, on_close, on_error, nil)

      assert.equals(1, #tcp._write_buffer)
      assert.is_true(client.handshake_complete)
      assert.equals("connected", client.state)
    end)

    it("validates auth token during handshake", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      local token = "valid-auth-token-12345"

      client_module.process_data(client, make_handshake_request(token), on_message, on_close, on_error, token)

      assert.is_true(client.handshake_complete)
      assert.equals("connected", client.state)
    end)

    it("rejects invalid auth token during handshake", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)

      client_module.process_data(client, make_handshake_request("wrong-token"), on_message, on_close, on_error, "correct-token")

      assert.is_false(client.handshake_complete)
      assert.equals("closing", client.state)
      vim.wait(100, function()
        return tcp._closed
      end)
      assert.is_true(tcp._closed)
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
      client_module.process_data(client, make_handshake_request(), on_message, on_close, on_error, nil)
      reset_callbacks()

      local masked_frame = string.char(0x81, 0x86, 0x00, 0x00, 0x00, 0x00) .. "Hello!"
      client_module.process_data(client, masked_frame, on_message, on_close, on_error, nil)

      assert.is_true(vim.wait(100, function()
        return #on_message_calls == 1
      end))
      assert.equals(1, #on_message_calls)
      assert.equals("Hello!", on_message_calls[1].message)
      assert.equals("", client.buffer)
    end)

    it("processes ping frame and sends pong", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client_module.process_data(client, make_handshake_request(), on_message, on_close, on_error, nil)
      local initial_writes = #tcp._write_buffer

      local ping_frame = string.char(0x89, 0x84, 0x00, 0x00, 0x00, 0x00) .. "ping"
      client_module.process_data(client, ping_frame, on_message, on_close, on_error, nil)

      assert.equals(initial_writes + 1, #tcp._write_buffer)
    end)

    it("handles close frame", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client_module.process_data(client, make_handshake_request(), on_message, on_close, on_error, nil)
      reset_callbacks()
      local initial_writes = #tcp._write_buffer

      local close_frame = string.char(0x88, 0x82, 0x00, 0x00, 0x00, 0x00, 0x03, 0xE8)
      client_module.process_data(client, close_frame, on_message, on_close, on_error, nil)

      assert.equals(initial_writes + 1, #tcp._write_buffer)
      assert.equals("closing", client.state)
      assert.is_true(vim.wait(100, function()
        return #on_close_calls == 1
      end))
      assert.equals(1, #on_close_calls)
      assert.equals(1000, on_close_calls[1].code)
    end)

    it("updates last_pong on pong frame", function()
      local tcp = create_mock_tcp()
      local client = client_module.create_client(tcp)
      client_module.process_data(client, make_handshake_request(), on_message, on_close, on_error, nil)
      client.last_pong = 0
      vim.loop.now = function()
        return 2000
      end

      local pong_frame = string.char(0x8A, 0x80, 0x00, 0x00, 0x00, 0x00)
      client_module.process_data(client, pong_frame, on_message, on_close, on_error, nil)

      assert.equals(2000, client.last_pong)
    end)
  end)
end)
