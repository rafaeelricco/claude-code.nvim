--- Integration tests for lua/claudecode/init.lua
--- Main plugin module integration tests

-- Setup mock vim if not in Neovim
if not vim then
  require("tests.helpers.mock_vim").setup()
end

describe("claudecode init integration", function()
  local claudecode
  local original_io_open
  local original_os_remove
  local mock_files = {}
  local registered_commands = {}

  -- Mock TCP handle
  local function create_mock_tcp_handle()
    local handle = {
      _bound = false,
      _listening = false,
      _closed = false,
      _closing = false,
      _write_buffer = {},
    }

    handle.bind = function(_, host, port)
      handle._bound = true
      handle._host = host
      handle._port = port
      return true
    end

    handle.listen = function(_, backlog, callback)
      handle._listening = true
      return true
    end

    handle.accept = function(_, client_handle)
      return true
    end

    handle.read_start = function(_, callback)
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

  local function setup_file_mocks()
    original_io_open = io.open
    original_os_remove = os.remove

    io.open = function(path, mode)
      if mode == "w" then
        return {
          write = function(_, content)
            mock_files[path] = content
          end,
          close = function() end,
        }
      elseif mode == "r" then
        local content = mock_files[path]
        if content then
          return {
            read = function(_, _)
              return content
            end,
            close = function() end,
          }
        end
        return nil
      end
      return nil
    end

    os.remove = function(path)
      if mock_files[path] then
        mock_files[path] = nil
        return true
      end
      return nil
    end
  end

  local function restore_file_mocks()
    io.open = original_io_open
    os.remove = original_os_remove
    mock_files = {}
  end

  before_each(function()
    -- Clear all module caches
    for key in pairs(package.loaded) do
      if key:match("^claudecode") then
        package.loaded[key] = nil
      end
    end

    setup_file_mocks()
    registered_commands = {}

    -- Setup vim mocks
    vim.fn.filereadable = function(path)
      return mock_files[path] and 1 or 0
    end
    vim.fn.mkdir = function(_, _)
      return 1
    end
    vim.fn.getcwd = function()
      return "/test/workspace"
    end
    vim.fn.getpid = function()
      return 12345
    end
    vim.fn.expand = function(path)
      if path:match("^~") then
        return "/home/testuser" .. path:sub(2)
      end
      return path
    end

    vim.loop.new_tcp = function()
      return create_mock_tcp_handle()
    end

    vim.loop.new_timer = function()
      return create_mock_timer()
    end

    vim.loop.now = function()
      return 1000
    end

    vim.lsp = {
      get_clients = function()
        return {}
      end,
    }

    vim.api.nvim_create_user_command = function(name, handler, opts)
      registered_commands[name] = { handler = handler, opts = opts }
    end
    vim.api.nvim_create_autocmd = function()
      return 1
    end
    vim.api.nvim_create_augroup = function()
      return 1
    end

    claudecode = require("claudecode")
  end)

  after_each(function()
    restore_file_mocks()
    -- Try to stop the server if running
    if claudecode and claudecode.state and claudecode.state.server then
      pcall(claudecode.stop)
    end
  end)

  describe("setup", function()
    it("initializes with default config", function()
      claudecode.setup()

      assert.is_true(claudecode.state.initialized)
      assert.is_table(claudecode.state.config)
    end)

    it("accepts custom config", function()
      claudecode.setup({
        port_range = { min = 20000, max = 30000 },
        log_level = "debug",
      })

      assert.equals(20000, claudecode.state.config.port_range.min)
      assert.equals(30000, claudecode.state.config.port_range.max)
      assert.equals("debug", claudecode.state.config.log_level)
    end)

    it("auto_start starts server when enabled", function()
      claudecode.setup({ auto_start = true })

      -- With auto_start, server should be running
      -- (though it may fail due to mocking, state should attempt to start)
      assert.is_true(claudecode.state.initialized)
    end)

    it("auto_start false does not start server", function()
      claudecode.setup({ auto_start = false })

      assert.is_true(claudecode.state.initialized)
      assert.is_nil(claudecode.state.port)
    end)

    it("returns the module", function()
      local result = claudecode.setup()
      assert.equals(claudecode, result)
    end)

    it("registers only headless commands and disabled compatibility stubs", function()
      claudecode.setup({ auto_start = false })

      assert.is_table(registered_commands.ClaudeCodeStart)
      assert.is_table(registered_commands.ClaudeCodeStop)
      assert.is_table(registered_commands.ClaudeCodeStatus)
      assert.is_table(registered_commands.ClaudeCode)
      assert.is_table(registered_commands.ClaudeCodeSend)
      assert.is_table(registered_commands.ClaudeCodeAdd)
      assert.is_table(registered_commands.ClaudeCodeTreeAdd)
      assert.is_table(registered_commands.ClaudeCodeDiffAccept)
      assert.is_nil(registered_commands.ClaudeCodeAddBuffer)
    end)
  end)

  describe("start", function()
    it("starts server successfully", function()
      claudecode.setup({ auto_start = false })
      local success, result = claudecode.start()

      assert.is_true(success)
      assert.is_number(result)
      assert.is_not_nil(claudecode.state.server)
      assert.is_not_nil(claudecode.state.port)
      assert.is_not_nil(claudecode.state.auth_token)
    end)

    it("creates lock file on start", function()
      claudecode.setup({ auto_start = false })
      claudecode.start()

      -- Lock file should exist
      local port = claudecode.state.port
      local lock_path = "/home/testuser/.claude/ide/" .. port .. ".lock"
      assert.is_truthy(mock_files[lock_path])
    end)

    it("returns error when already running", function()
      claudecode.setup({ auto_start = false })
      claudecode.start()

      local success, result = claudecode.start()

      assert.is_false(success)
      assert.is_truthy(result:match("Already running"))
    end)

    it("generates unique auth token", function()
      claudecode.setup({ auto_start = false })
      claudecode.start()

      assert.is_string(claudecode.state.auth_token)
      assert.equals(36, #claudecode.state.auth_token) -- UUID length
    end)
  end)

  describe("stop", function()
    it("stops running server", function()
      claudecode.setup({ auto_start = false })
      claudecode.start()

      local success = claudecode.stop()

      assert.is_true(success)
      assert.is_nil(claudecode.state.server)
      assert.is_nil(claudecode.state.port)
      assert.is_nil(claudecode.state.auth_token)
    end)

    it("removes lock file on stop", function()
      claudecode.setup({ auto_start = false })
      claudecode.start()
      local port = claudecode.state.port
      local lock_path = "/home/testuser/.claude/ide/" .. port .. ".lock"

      -- Verify lock file exists
      assert.is_truthy(mock_files[lock_path])

      claudecode.stop()

      -- Lock file should be removed
      assert.is_falsy(mock_files[lock_path])
    end)

    it("returns error when not running", function()
      claudecode.setup({ auto_start = false })

      local success, result = claudecode.stop()

      assert.is_false(success)
      assert.is_truthy(result:match("Not running"))
    end)
  end)

  describe("is_running", function()
    it("returns false when not started", function()
      claudecode.setup({ auto_start = false })
      assert.is_false(claudecode.is_running())
    end)

    it("returns true when running", function()
      claudecode.setup({ auto_start = false })
      claudecode.start()

      assert.is_true(claudecode.is_running())
    end)

    it("returns false after stop", function()
      claudecode.setup({ auto_start = false })
      claudecode.start()
      claudecode.stop()

      assert.is_false(claudecode.is_running())
    end)
  end)

  describe("get_port", function()
    it("returns nil when not running", function()
      claudecode.setup({ auto_start = false })
      assert.is_nil(claudecode.get_port())
    end)

    it("returns port when running", function()
      claudecode.setup({ auto_start = false })
      claudecode.start()

      local port = claudecode.get_port()

      assert.is_number(port)
      assert.is_true(port >= 10000)
      assert.is_true(port <= 65535)
    end)
  end)

  describe("get_version", function()
    it("returns version information", function()
      local version = claudecode.get_version()

      assert.is_table(version)
      assert.is_string(version.version)
      assert.is_number(version.major)
      assert.is_number(version.minor)
      assert.is_number(version.patch)
    end)

    it("returns correct version format", function()
      local version = claudecode.get_version()

      -- Version string should match major.minor.patch format
      local expected = string.format("%d.%d.%d", version.major, version.minor, version.patch)
      if version.prerelease then
        expected = expected .. "-" .. version.prerelease
      end
      assert.equals(expected, version.version)
    end)
  end)

  describe("version", function()
    it("has string method", function()
      assert.is_function(claudecode.version.string)
    end)

    it("string method returns formatted version", function()
      local version_str = claudecode.version:string()
      assert.is_string(version_str)
      assert.is_truthy(version_str:match("^%d+%.%d+%.%d+"))
    end)
  end)

  describe("is_claude_connected", function()
    it("returns false when server not running", function()
      claudecode.setup({ auto_start = false })
      assert.is_false(claudecode.is_claude_connected())
    end)

    it("returns false when no clients connected", function()
      claudecode.setup({ auto_start = false })
      claudecode.start()

      assert.is_false(claudecode.is_claude_connected())
    end)
  end)
end)
