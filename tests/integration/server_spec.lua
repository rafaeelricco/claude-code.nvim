--- Integration tests for lua/claudecode/server/init.lua
--- WebSocket server integration tests

-- Setup mock vim if not in Neovim
if not vim then
  require("tests.helpers.mock_vim").setup()
end

describe("server integration", function()
  local server
  local frame

  -- Mock TCP handle
  local function create_mock_tcp_handle()
    local handle = {
      _bound = false,
      _listening = false,
      _closed = false,
      _closing = false,
      _write_buffer = {},
      _on_connection = nil,
    }

    handle.bind = function(_, host, port)
      handle._bound = true
      handle._host = host
      handle._port = port
      return true
    end

    handle.listen = function(_, backlog, callback)
      handle._listening = true
      handle._on_connection = callback
      return true
    end

    handle.accept = function(_, client_handle)
      return true
    end

    handle.read_start = function(_, callback)
      handle._read_callback = callback
      return 0
    end

    handle.write = function(_, data, callback)
      table.insert(handle._write_buffer, data)
      if callback then
        callback(nil)
      end
    end

    handle.close = function(_, callback)
      handle._closed = true
      handle._closing = true
      if callback then
        callback()
      end
    end

    handle.is_closing = function()
      return handle._closing
    end

    return handle
  end

  -- Mock timer
  local function create_mock_timer()
    local timer = {
      _running = false,
    }

    timer.start = function(_, timeout, repeat_ms, callback)
      timer._running = true
      return true
    end

    timer.stop = function()
      timer._running = false
      return true
    end

    timer.close = function(_, callback)
      timer._running = false
      if callback then
        callback()
      end
    end

    return timer
  end

  before_each(function()
    -- Clear all module caches
    for key in pairs(package.loaded) do
      if key:match("^claudecode") then
        package.loaded[key] = nil
      end
    end

    -- Setup vim mocks
    vim.loop.new_tcp = function()
      return create_mock_tcp_handle()
    end

    vim.loop.new_timer = function()
      return create_mock_timer()
    end

    vim.loop.now = function()
      return 1000
    end

    vim.empty_dict = vim.empty_dict or function()
      return {}
    end

    -- Clear global state
    _G.claude_deferred_responses = nil

    -- Load modules
    frame = require("claudecode.server.frame")
    server = require("claudecode.server.init")
  end)

  after_each(function()
    -- Try to stop the server if running
    if server and server.state and server.state.server then
      pcall(server.stop)
    end
  end)

  describe("start", function()
    it("starts server successfully", function()
      local config = { port_range = { min = 10000, max = 65535 } }
      local success, port = server.start(config)

      assert.is_true(success)
      assert.is_number(port)
      assert.is_not_nil(server.state.server)
      assert.is_not_nil(server.state.port)
    end)

    it("starts with auth token", function()
      local config = { port_range = { min = 10000, max = 65535 } }
      local auth_token = "test-auth-token-12345"
      local success = server.start(config, auth_token)

      assert.is_true(success)
      assert.equals(auth_token, server.state.auth_token)
    end)

    it("returns error when already running", function()
      local config = { port_range = { min = 10000, max = 65535 } }
      server.start(config)

      local success, error_msg = server.start(config)

      assert.is_false(success)
      assert.is_truthy(error_msg:match("already running"))
    end)

    it("registers MCP handlers", function()
      local config = { port_range = { min = 10000, max = 65535 } }
      server.start(config)

      assert.is_table(server.state.handlers)
      assert.is_function(server.state.handlers["initialize"])
      assert.is_function(server.state.handlers["tools/list"])
      assert.is_function(server.state.handlers["tools/call"])
    end)
  end)

  describe("stop", function()
    it("stops running server", function()
      local config = { port_range = { min = 10000, max = 65535 } }
      server.start(config)

      local success = server.stop()

      assert.is_true(success)
      assert.is_nil(server.state.server)
      assert.is_nil(server.state.port)
    end)

    it("returns error when not running", function()
      local success, error_msg = server.stop()

      assert.is_false(success)
      assert.is_truthy(error_msg:match("not running"))
    end)

    it("clears auth token on stop", function()
      local config = { port_range = { min = 10000, max = 65535 } }
      server.start(config, "test-token")

      server.stop()

      assert.is_nil(server.state.auth_token)
    end)

    it("clears deferred responses on stop", function()
      local config = { port_range = { min = 10000, max = 65535 } }
      server.start(config)

      _G.claude_deferred_responses = { test = function() end }

      server.stop()

      assert.is_table(_G.claude_deferred_responses)
      assert.equals(0, vim.tbl_count(_G.claude_deferred_responses or {}))
    end)
  end)

  describe("get_status", function()
    it("returns not running status when stopped", function()
      local status = server.get_status()

      assert.is_false(status.running)
      assert.is_nil(status.port)
      assert.equals(0, status.client_count)
    end)

    it("returns running status when started", function()
      local config = { port_range = { min = 10000, max = 65535 } }
      server.start(config)

      local status = server.get_status()

      assert.is_true(status.running)
      assert.is_number(status.port)
      assert.equals(0, status.client_count)
    end)
  end)

  describe("MCP handlers", function()
    before_each(function()
      local config = { port_range = { min = 10000, max = 65535 } }
      server.start(config)
    end)

    describe("initialize", function()
      it("returns protocol version", function()
        local result = server.state.handlers["initialize"]({}, {})

        assert.is_string(result.protocolVersion)
        assert.equals("2024-11-05", result.protocolVersion)
      end)

      it("returns capabilities", function()
        local result = server.state.handlers["initialize"]({}, {})

        assert.is_table(result.capabilities)
        assert.is_table(result.capabilities.tools)
      end)

      it("returns server info", function()
        local result = server.state.handlers["initialize"]({}, {})

        assert.is_table(result.serverInfo)
        assert.equals("claudecode-neovim", result.serverInfo.name)
        assert.is_string(result.serverInfo.version)
      end)
    end)

    describe("tools/list", function()
      it("returns empty tools array", function()
        local result = server.state.handlers["tools/list"]({}, {})

        assert.is_table(result)
        assert.is_table(result.tools)
        assert.equals(0, #result.tools)
      end)
    end)

    describe("tools/call", function()
      it("returns error for any tool call", function()
        local result, error_data = server.state.handlers["tools/call"]({}, { name = "openFile" })

        assert.is_nil(result)
        assert.is_table(error_data)
        assert.equals(-32601, error_data.code)
        assert.is_truthy(error_data.message:match("No tools"))
      end)
    end)

    describe("prompts/list", function()
      it("returns empty prompts array", function()
        local result = server.state.handlers["prompts/list"]({}, {})

        assert.is_table(result)
        assert.is_table(result.prompts)
        assert.equals(0, #result.prompts)
      end)
    end)
  end)

  describe("send", function()
    it("returns false when server not running", function()
      local client = { id = "test" }
      local result = server.send(client, "test", {})

      assert.is_false(result)
    end)

    it("returns true when server running", function()
      local config = { port_range = { min = 10000, max = 65535 } }
      server.start(config)

      -- Create mock client
      local tcp_handle = create_mock_tcp_handle()
      local client = require("claudecode.server.client").create_client(tcp_handle)
      client.state = "connected"
      server.state.server.clients[client.id] = client

      local result = server.send(client, "test/method", { data = "test" })

      assert.is_true(result)
    end)
  end)

  describe("send_response", function()
    it("returns false when server not running", function()
      local client = { id = "test" }
      local result = server.send_response(client, 1, { test = true }, nil)

      assert.is_false(result)
    end)

    it("sends success response", function()
      local config = { port_range = { min = 10000, max = 65535 } }
      server.start(config)

      local tcp_handle = create_mock_tcp_handle()
      local client = require("claudecode.server.client").create_client(tcp_handle)
      client.state = "connected"
      server.state.server.clients[client.id] = client

      local result = server.send_response(client, 1, { data = "success" }, nil)

      assert.is_true(result)
      assert.equals(1, #tcp_handle._write_buffer)
    end)

    it("sends error response", function()
      local config = { port_range = { min = 10000, max = 65535 } }
      server.start(config)

      local tcp_handle = create_mock_tcp_handle()
      local client = require("claudecode.server.client").create_client(tcp_handle)
      client.state = "connected"
      server.state.server.clients[client.id] = client

      local result = server.send_response(client, 1, nil, { code = -32600, message = "Error" })

      assert.is_true(result)
      assert.equals(1, #tcp_handle._write_buffer)
    end)
  end)

  describe("broadcast", function()
    it("returns false when server not running", function()
      local result = server.broadcast("test/method", {})

      assert.is_false(result)
    end)

    it("broadcasts to all clients", function()
      local config = { port_range = { min = 10000, max = 65535 } }
      server.start(config)

      local tcp_handle1 = create_mock_tcp_handle()
      local tcp_handle2 = create_mock_tcp_handle()
      local client1 = require("claudecode.server.client").create_client(tcp_handle1)
      local client2 = require("claudecode.server.client").create_client(tcp_handle2)
      client1.state = "connected"
      client2.state = "connected"
      server.state.server.clients[client1.id] = client1
      server.state.server.clients[client2.id] = client2

      local result = server.broadcast("test/method", { data = "broadcast" })

      assert.is_true(result)
      assert.equals(1, #tcp_handle1._write_buffer)
      assert.equals(1, #tcp_handle2._write_buffer)
    end)
  end)

  describe("_handle_message", function()
    before_each(function()
      local config = { port_range = { min = 10000, max = 65535 } }
      server.start(config)
    end)

    it("handles valid JSON-RPC request", function()
      local tcp_handle = create_mock_tcp_handle()
      local client = require("claudecode.server.client").create_client(tcp_handle)
      client.state = "connected"
      server.state.server.clients[client.id] = client

      local message = vim.json.encode({
        jsonrpc = "2.0",
        id = 1,
        method = "initialize",
        params = {},
      })

      server._handle_message(client, message)

      -- Should send a response
      assert.equals(1, #tcp_handle._write_buffer)
    end)

    it("handles invalid JSON", function()
      local tcp_handle = create_mock_tcp_handle()
      local client = require("claudecode.server.client").create_client(tcp_handle)
      client.state = "connected"
      server.state.server.clients[client.id] = client

      server._handle_message(client, "not valid json")

      -- Should send error response
      assert.equals(1, #tcp_handle._write_buffer)
      local response = vim.json.decode(tcp_handle._write_buffer[1])
      assert.equals(-32700, response.error.code)
    end)

    it("handles invalid JSON-RPC", function()
      local tcp_handle = create_mock_tcp_handle()
      local client = require("claudecode.server.client").create_client(tcp_handle)
      client.state = "connected"
      server.state.server.clients[client.id] = client

      local message = vim.json.encode({
        not_jsonrpc = true,
      })

      server._handle_message(client, message)

      -- Should send error response
      assert.equals(1, #tcp_handle._write_buffer)
      local response = vim.json.decode(tcp_handle._write_buffer[1])
      assert.equals(-32600, response.error.code)
    end)

    it("handles unknown method", function()
      local tcp_handle = create_mock_tcp_handle()
      local client = require("claudecode.server.client").create_client(tcp_handle)
      client.state = "connected"
      server.state.server.clients[client.id] = client

      local message = vim.json.encode({
        jsonrpc = "2.0",
        id = 1,
        method = "unknown/method",
        params = {},
      })

      server._handle_message(client, message)

      -- Should send error response
      assert.equals(1, #tcp_handle._write_buffer)
      local response = vim.json.decode(tcp_handle._write_buffer[1])
      assert.equals(-32601, response.error.code)
    end)

    it("handles notification (no id)", function()
      local tcp_handle = create_mock_tcp_handle()
      local client = require("claudecode.server.client").create_client(tcp_handle)
      client.state = "connected"
      server.state.server.clients[client.id] = client

      local message = vim.json.encode({
        jsonrpc = "2.0",
        method = "notifications/initialized",
        params = {},
      })

      -- Should not throw
      server._handle_message(client, message)

      -- Notifications don't get responses
      assert.equals(0, #tcp_handle._write_buffer)
    end)
  end)
end)
