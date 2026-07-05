--- Tests for lua/claudecode/server/tcp.lua

if not vim then
  require("tests.helpers.mock_vim").setup()
end

describe("server/tcp", function()
  local client_module
  local tcp_module

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

    handle.listen = function(_, _, callback)
      if not handle._bound then
        return nil, "Not bound"
      end
      handle._listening = true
      handle._on_connection = callback
      return true
    end

    handle.accept = function()
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

  local function create_mock_timer()
    local timer = {
      _running = false,
      _callback = nil,
      _interval = 0,
    }

    timer.start = function(_, _, repeat_ms, callback)
      timer._running = true
      timer._callback = callback
      timer._interval = repeat_ms
      return true
    end

    timer._trigger = function()
      if timer._callback then
        timer._callback()
      end
    end

    return timer
  end

  before_each(function()
    package.loaded["claudecode.server.tcp"] = nil
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

    vim.loop.new_tcp = function()
      return create_mock_tcp_handle()
    end
    vim.loop.new_timer = function()
      return create_mock_timer()
    end
    vim.loop.now = function()
      return 1000
    end

    client_module = require("claudecode.server.client")
    tcp_module = require("claudecode.server.tcp")
  end)

  describe("port selection", function()
    it("finds ports in range and handles exhausted ranges", function()
      assert.is_number(tcp_module.find_available_port(10000, 10010))

      vim.loop.new_tcp = function()
        local handle = create_mock_tcp_handle()
        handle.bind = function()
          return nil, "Address in use"
        end
        return handle
      end

      assert.is_nil(tcp_module.find_available_port(10000, 10002))
    end)
  end)

  describe("server lifecycle", function()
    it("creates and stops a server", function()
      local server = tcp_module.create_server({ port_range = { min = 10000, max = 10100 } }, {}, "token")

      assert.is_number(server.port)
      assert.equals("token", server.auth_token)
      assert.equals(0, tcp_module.get_client_count(server))

      tcp_module.stop_server(server)

      assert.equals(0, tcp_module.get_client_count(server))
      assert.is_true(server.server._closed)
    end)

    it("returns an error when no ports are available", function()
      vim.loop.new_tcp = function()
        local handle = create_mock_tcp_handle()
        handle.bind = function()
          return nil, "Address in use"
        end
        return handle
      end

      local server, err = tcp_module.create_server({ port_range = { min = 10000, max = 10002 } }, {}, nil)

      assert.is_nil(server)
      assert.is_truthy(err:match("No available ports"))
    end)
  end)

  describe("send_to_client", function()
    it("sends to an existing client and reports missing clients", function()
      local server = tcp_module.create_server({ port_range = { min = 10000, max = 10100 } }, {}, nil)
      local client_tcp = create_mock_tcp_handle()
      local client = client_module.create_client(client_tcp)
      client.state = "connected"
      server.clients[client.id] = client

      local send_error
      tcp_module.send_to_client(server, client.id, "Hello!", function(err)
        send_error = err
      end)

      assert.is_nil(send_error)
      assert.equals(1, #client_tcp._write_buffer)

      local missing_error
      tcp_module.send_to_client(server, "missing", "Hello!", function(err)
        missing_error = err
      end)

      assert.is_truthy(missing_error:match("not found"))
    end)
  end)

  describe("start_ping_timer", function()
    it("pings alive clients", function()
      local server = tcp_module.create_server({ port_range = { min = 10000, max = 10100 } }, {}, nil)
      local client_tcp = create_mock_tcp_handle()
      local client = client_module.create_client(client_tcp)
      client.state = "connected"
      client.last_pong = vim.loop.now()
      server.clients[client.id] = client

      local timer = tcp_module.start_ping_timer(server)
      timer._trigger()

      assert.equals(1, #client_tcp._write_buffer)
    end)

    it("closes stale clients", function()
      local disconnected = false
      local server = tcp_module.create_server({
        port_range = { min = 10000, max = 10100 },
      }, {
        on_disconnect = function()
          disconnected = true
        end,
      }, nil)
      local client_tcp = create_mock_tcp_handle()
      local client = client_module.create_client(client_tcp)
      client.state = "connected"
      client.handshake_complete = true
      client.last_pong = vim.loop.now() - 120000
      server.clients[client.id] = client

      local timer = tcp_module.start_ping_timer(server, 30000)
      timer._trigger()

      assert.is_true(disconnected)
      assert.equals("closed", client.state)
      assert.is_nil(server.clients[client.id])
    end)
  end)
end)
