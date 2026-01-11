--- Tests for lua/claudecode/server/tcp.lua
--- TCP server implementation

-- Setup mock vim if not in Neovim
if not vim then
  require("tests.helpers.mock_vim").setup()
end

describe("server/tcp", function()
  local tcp_module
  local client_module

  -- Mock TCP handle
  local function create_mock_tcp_handle()
    local handle = {
      _bound = false,
      _listening = false,
      _closed = false,
      _closing = false,
      _write_buffer = {},
      _on_connection = nil,
      _read_callback = nil,
    }

    handle.bind = function(_, host, port)
      if handle._closed then
        return nil, "Handle closed"
      end
      handle._bound = true
      handle._host = host
      handle._port = port
      return true
    end

    handle.listen = function(_, backlog, callback)
      if not handle._bound then
        return nil, "Not bound"
      end
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

    handle.read_stop = function()
      handle._read_callback = nil
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

    handle.getsockname = function()
      return { ip = handle._host or "127.0.0.1", port = handle._port or 0 }
    end

    -- Helper to simulate incoming connection
    handle._trigger_connection = function()
      if handle._on_connection then
        handle._on_connection(nil)
      end
    end

    -- Helper to simulate data received
    handle._receive_data = function(data)
      if handle._read_callback then
        handle._read_callback(nil, data)
      end
    end

    -- Helper to simulate EOF
    handle._receive_eof = function()
      if handle._read_callback then
        handle._read_callback(nil, nil)
      end
    end

    return handle
  end

  -- Mock timer handle
  local function create_mock_timer()
    local timer = {
      _running = false,
      _callback = nil,
      _interval = 0,
    }

    timer.start = function(_, timeout, repeat_ms, callback)
      timer._running = true
      timer._callback = callback
      timer._interval = repeat_ms
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

    timer._trigger = function()
      if timer._callback then
        timer._callback()
      end
    end

    return timer
  end

  before_each(function()
    -- Clear module cache
    package.loaded["claudecode.server.tcp"] = nil
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

    -- Mock vim.loop
    vim.loop.new_tcp = function()
      return create_mock_tcp_handle()
    end

    vim.loop.new_timer = function()
      return create_mock_timer()
    end

    vim.loop.now = function()
      return 1000
    end

    -- Load modules
    client_module = require("claudecode.server.client")
    tcp_module = require("claudecode.server.tcp")
  end)

  describe("find_available_port", function()
    it("returns port in valid range", function()
      local port = tcp_module.find_available_port(10000, 10010)
      assert.is_number(port)
      assert.is_true(port >= 10000)
      assert.is_true(port <= 10010)
    end)

    it("returns nil when min > max", function()
      local port = tcp_module.find_available_port(10010, 10000)
      assert.is_nil(port)
    end)

    it("works with single port range", function()
      local port = tcp_module.find_available_port(12345, 12345)
      assert.equals(12345, port)
    end)

    it("returns nil when no ports available", function()
      -- Mock bind to always fail
      vim.loop.new_tcp = function()
        local handle = create_mock_tcp_handle()
        handle.bind = function()
          return nil, "Address in use"
        end
        return handle
      end

      local port = tcp_module.find_available_port(10000, 10002)
      assert.is_nil(port)
    end)
  end)

  describe("create_server", function()
    it("creates server successfully", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {
        on_message = function() end,
        on_connect = function() end,
        on_disconnect = function() end,
        on_error = function() end,
      }

      local server, err = tcp_module.create_server(config, callbacks, nil)

      assert.is_not_nil(server)
      assert.is_nil(err)
      assert.is_number(server.port)
    end)

    it("returns error when no ports available", function()
      vim.loop.new_tcp = function()
        local handle = create_mock_tcp_handle()
        handle.bind = function()
          return nil, "Address in use"
        end
        return handle
      end

      local config = { port_range = { min = 10000, max = 10002 } }
      local callbacks = {}

      local server, err = tcp_module.create_server(config, callbacks, nil)

      assert.is_nil(server)
      assert.is_truthy(err:match("No available ports"))
    end)

    it("stores auth token", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local token = "test-auth-token-123"

      local server = tcp_module.create_server(config, callbacks, token)

      assert.equals(token, server.auth_token)
    end)

    it("initializes empty clients table", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}

      local server = tcp_module.create_server(config, callbacks, nil)

      assert.is_table(server.clients)
      assert.equals(0, tcp_module.get_client_count(server))
    end)

    it("stores callbacks", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local message_fn = function() end
      local connect_fn = function() end
      local disconnect_fn = function() end
      local error_fn = function() end
      local callbacks = {
        on_message = message_fn,
        on_connect = connect_fn,
        on_disconnect = disconnect_fn,
        on_error = error_fn,
      }

      local server = tcp_module.create_server(config, callbacks, nil)

      assert.equals(message_fn, server.on_message)
      assert.equals(connect_fn, server.on_connect)
      assert.equals(disconnect_fn, server.on_disconnect)
      assert.equals(error_fn, server.on_error)
    end)

    it("provides default callbacks when not specified", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}

      local server = tcp_module.create_server(config, callbacks, nil)

      assert.is_function(server.on_message)
      assert.is_function(server.on_connect)
      assert.is_function(server.on_disconnect)
      assert.is_function(server.on_error)
    end)
  end)

  describe("send_to_client", function()
    it("sends message to existing client", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      -- Create a mock client
      local mock_tcp = create_mock_tcp_handle()
      local client = client_module.create_client(mock_tcp)
      client.state = "connected"
      server.clients[client.id] = client

      local callback_called = false
      tcp_module.send_to_client(server, client.id, "Hello!", function(err)
        callback_called = true
        assert.is_nil(err)
      end)

      assert.is_true(callback_called)
      assert.equals(1, #mock_tcp._write_buffer)
    end)

    it("returns error for non-existent client", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      local callback_called = false
      local callback_error = nil
      tcp_module.send_to_client(server, "non-existent-id", "Hello!", function(err)
        callback_called = true
        callback_error = err
      end)

      assert.is_true(callback_called)
      assert.is_truthy(callback_error:match("not found"))
    end)

    it("works without callback", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      -- Should not throw
      tcp_module.send_to_client(server, "non-existent-id", "Hello!")
    end)
  end)

  describe("broadcast", function()
    it("sends message to all connected clients", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      -- Create multiple mock clients
      local tcp1 = create_mock_tcp_handle()
      local tcp2 = create_mock_tcp_handle()
      local client1 = client_module.create_client(tcp1)
      local client2 = client_module.create_client(tcp2)
      client1.state = "connected"
      client2.state = "connected"
      server.clients[client1.id] = client1
      server.clients[client2.id] = client2

      tcp_module.broadcast(server, "Broadcast message")

      assert.equals(1, #tcp1._write_buffer)
      assert.equals(1, #tcp2._write_buffer)
    end)

    it("does nothing with no clients", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      -- Should not throw
      tcp_module.broadcast(server, "Broadcast message")
    end)
  end)

  describe("get_client_count", function()
    it("returns 0 for empty server", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      assert.equals(0, tcp_module.get_client_count(server))
    end)

    it("returns correct count with clients", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      -- Add mock clients
      local tcp1 = create_mock_tcp_handle()
      local tcp2 = create_mock_tcp_handle()
      local tcp3 = create_mock_tcp_handle()
      server.clients["client1"] = client_module.create_client(tcp1)
      server.clients["client2"] = client_module.create_client(tcp2)
      server.clients["client3"] = client_module.create_client(tcp3)

      assert.equals(3, tcp_module.get_client_count(server))
    end)
  end)

  describe("get_clients_info", function()
    it("returns empty array for empty server", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      local info = tcp_module.get_clients_info(server)

      assert.is_table(info)
      assert.equals(0, #info)
    end)

    it("returns info for all clients", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      -- Add mock clients
      local tcp1 = create_mock_tcp_handle()
      local tcp2 = create_mock_tcp_handle()
      server.clients["client1"] = client_module.create_client(tcp1)
      server.clients["client2"] = client_module.create_client(tcp2)

      local info = tcp_module.get_clients_info(server)

      assert.equals(2, #info)
      for _, client_info in ipairs(info) do
        assert.is_string(client_info.id)
        assert.is_string(client_info.state)
        assert.is_boolean(client_info.handshake_complete)
      end
    end)
  end)

  describe("close_client", function()
    it("closes existing client", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      -- Add mock client
      local mock_tcp = create_mock_tcp_handle()
      local client = client_module.create_client(mock_tcp)
      client.state = "connected"
      client.handshake_complete = true
      server.clients[client.id] = client

      tcp_module.close_client(server, client.id, 1000, "Normal closure")

      assert.equals("closing", client.state)
    end)

    it("does nothing for non-existent client", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      -- Should not throw
      tcp_module.close_client(server, "non-existent-id", 1000, "Closure")
    end)
  end)

  describe("stop_server", function()
    it("closes all clients", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      -- Add mock clients
      local tcp1 = create_mock_tcp_handle()
      local tcp2 = create_mock_tcp_handle()
      local client1 = client_module.create_client(tcp1)
      local client2 = client_module.create_client(tcp2)
      client1.state = "connected"
      client1.handshake_complete = true
      client2.state = "connected"
      client2.handshake_complete = true
      server.clients[client1.id] = client1
      server.clients[client2.id] = client2

      tcp_module.stop_server(server)

      assert.equals("closing", client1.state)
      assert.equals("closing", client2.state)
    end)

    it("clears clients table", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      -- Add mock client
      local tcp1 = create_mock_tcp_handle()
      server.clients["client1"] = client_module.create_client(tcp1)

      tcp_module.stop_server(server)

      assert.equals(0, tcp_module.get_client_count(server))
    end)

    it("closes server handle", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      tcp_module.stop_server(server)

      assert.is_true(server.server._closed)
    end)

    it("handles already closed server", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)
      server.server._closing = true

      -- Should not throw
      tcp_module.stop_server(server)
    end)
  end)

  describe("start_ping_timer", function()
    it("creates timer", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      local timer = tcp_module.start_ping_timer(server)

      assert.is_table(timer)
      assert.is_true(timer._running)
    end)

    it("uses default 30 second interval", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      local timer = tcp_module.start_ping_timer(server)

      assert.equals(30000, timer._interval)
    end)

    it("uses custom interval", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      local timer = tcp_module.start_ping_timer(server, 15000)

      assert.equals(15000, timer._interval)
    end)

    it("sends ping to connected clients", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      -- Add connected client
      local mock_tcp = create_mock_tcp_handle()
      local client = client_module.create_client(mock_tcp)
      client.state = "connected"
      client.last_pong = vim.loop.now() -- Recent pong
      server.clients[client.id] = client

      local timer = tcp_module.start_ping_timer(server)
      timer._trigger()

      -- Ping should have been sent
      assert.equals(1, #mock_tcp._write_buffer)
    end)

    it("closes dead clients", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local disconnect_called = false
      local callbacks = {
        on_disconnect = function()
          disconnect_called = true
        end,
      }
      local server = tcp_module.create_server(config, callbacks, nil)

      -- Add client with old pong time
      local mock_tcp = create_mock_tcp_handle()
      local client = client_module.create_client(mock_tcp)
      client.state = "connected"
      client.handshake_complete = true
      client.last_pong = vim.loop.now() - 120000 -- 2 minutes ago
      server.clients[client.id] = client

      local timer = tcp_module.start_ping_timer(server, 30000)
      timer._trigger()

      assert.is_true(disconnect_called)
      assert.equals("closing", client.state)
    end)
  end)

  describe("_remove_client", function()
    it("removes client from server", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      -- Add mock client
      local mock_tcp = create_mock_tcp_handle()
      local client = client_module.create_client(mock_tcp)
      server.clients[client.id] = client

      tcp_module._remove_client(server, client)

      assert.is_nil(server.clients[client.id])
    end)

    it("closes tcp handle", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      -- Add mock client
      local mock_tcp = create_mock_tcp_handle()
      local client = client_module.create_client(mock_tcp)
      server.clients[client.id] = client

      tcp_module._remove_client(server, client)

      assert.is_true(mock_tcp._closed)
    end)

    it("handles already closing handle", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      -- Add mock client
      local mock_tcp = create_mock_tcp_handle()
      mock_tcp._closing = true
      local client = client_module.create_client(mock_tcp)
      server.clients[client.id] = client

      -- Should not throw
      tcp_module._remove_client(server, client)

      assert.is_nil(server.clients[client.id])
    end)

    it("handles non-existent client", function()
      local config = { port_range = { min = 10000, max = 10100 } }
      local callbacks = {}
      local server = tcp_module.create_server(config, callbacks, nil)

      local mock_tcp = create_mock_tcp_handle()
      local client = client_module.create_client(mock_tcp)
      -- Not added to server.clients

      -- Should not throw
      tcp_module._remove_client(server, client)
    end)
  end)
end)
