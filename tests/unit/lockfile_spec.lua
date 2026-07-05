--- Tests for lua/claudecode/lockfile.lua

if not vim then
  require("tests.helpers.mock_vim").setup()
end

describe("lockfile", function()
  local lockfile
  local original_io_open
  local original_os_remove
  local original_os_getenv
  local mock_files

  local function setup_file_mocks()
    mock_files = {}
    original_io_open = io.open
    original_os_remove = os.remove
    original_os_getenv = os.getenv

    io.open = function(path, mode)
      if mode == "w" then
        return {
          write = function(_, content)
            mock_files[path] = content
          end,
          close = function() end,
        }
      end

      if mode == "r" and mock_files[path] then
        return {
          read = function()
            return mock_files[path]
          end,
          close = function() end,
        }
      end

      return nil
    end

    os.remove = function(path)
      if mock_files[path] then
        mock_files[path] = nil
        return true
      end
      return nil, "File not found"
    end

    os.getenv = function(name)
      if name == "CLAUDE_CONFIG_DIR" then
        return nil
      end
      return original_os_getenv(name)
    end
  end

  before_each(function()
    package.loaded["claudecode.lockfile"] = nil
    setup_file_mocks()

    vim.fn.filereadable = function(path)
      return mock_files[path] and 1 or 0
    end
    vim.fn.mkdir = function()
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
    vim.lsp = {
      get_clients = function()
        return {}
      end,
    }

    lockfile = require("claudecode.lockfile")
  end)

  after_each(function()
    io.open = original_io_open
    os.remove = original_os_remove
    os.getenv = original_os_getenv
  end)

  describe("generate_auth_token", function()
    it("generates UUIDv4-style auth tokens", function()
      local token = lockfile.generate_auth_token()

      assert.is_truthy(token:match("^[0-9a-f]+%-[0-9a-f]+%-4[0-9a-f]+%-[89ab][0-9a-f]+%-[0-9a-f]+$"))
      assert.equals(36, #token)
    end)
  end)

  describe("create", function()
    it("writes Claude discovery data with auth and workspace folders", function()
      local success, path, token = lockfile.create(12345, "custom-auth-token-12345678")
      assert.is_true(success)
      assert.is_truthy(path:match("12345%.lock$"))

      local data = vim.json.decode(mock_files[path])
      assert.equals(12345, data.pid)
      assert.equals("Neovim", data.ideName)
      assert.equals("ws", data.transport)
      assert.equals("custom-auth-token-12345678", data.authToken)
      assert.same({ "/test/workspace" }, data.workspaceFolders)
      assert.equals("custom-auth-token-12345678", token)
    end)

    it("rejects invalid port and auth token inputs", function()
      assert.is_false(lockfile.create(0))
      assert.is_false(lockfile.create(65536))
      assert.is_false(lockfile.create(12345, "short"))
      assert.is_false(lockfile.create(12345, string.rep("x", 501)))
    end)
  end)

  describe("remove", function()
    it("removes an existing lock file and rejects a missing one", function()
      local success, path = lockfile.create(12345)
      assert.is_true(success)

      assert.is_true(lockfile.remove(12345))
      assert.is_falsy(mock_files[path])
      assert.is_false(lockfile.remove(99999))
    end)
  end)

  describe("get_workspace_folders", function()
    it("includes cwd and LSP workspace folders once", function()
      vim.lsp.get_clients = function()
        return {
          {
            config = {
              workspace_folders = {
                { uri = "file:///test/workspace" },
                { uri = "file:///test/other" },
              },
            },
          },
        }
      end

      local folders = lockfile.get_workspace_folders()
      local cwd_count = 0
      local found_other = false
      for _, folder in ipairs(folders) do
        if folder == "/test/workspace" then
          cwd_count = cwd_count + 1
        elseif folder == "/test/other" then
          found_other = true
        end
      end

      assert.equals(1, cwd_count)
      assert.is_true(found_other)
    end)
  end)

  describe("lock_dir", function()
    it("respects CLAUDE_CONFIG_DIR environment variable", function()
      os.getenv = function(name)
        if name == "CLAUDE_CONFIG_DIR" then
          return "/custom/claude/config"
        end
        return original_os_getenv(name)
      end

      package.loaded["claudecode.lockfile"] = nil
      local new_lockfile = require("claudecode.lockfile")
      assert.equals("/custom/claude/config/ide", new_lockfile.lock_dir)
    end)
  end)
end)
