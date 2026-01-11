--- Tests for lua/claudecode/lockfile.lua
--- Lock file management for Claude Code discovery

-- Setup mock vim if not in Neovim
if not vim then
  require("tests.helpers.mock_vim").setup()
end

describe("lockfile", function()
  local lockfile
  local original_io_open
  local original_os_remove
  local original_os_getenv

  -- Mock file system for testing
  local mock_files = {}

  local function setup_file_mocks()
    original_io_open = io.open
    original_os_remove = os.remove
    original_os_getenv = os.getenv

    -- Mock io.open
    io.open = function(path, mode)
      if mode == "w" then
        -- Writing a file
        return {
          write = function(_, content)
            mock_files[path] = content
          end,
          close = function() end,
        }
      elseif mode == "r" then
        -- Reading a file
        local content = mock_files[path]
        if content then
          return {
            read = function(_, _)
              return content
            end,
            close = function() end,
          }
        else
          return nil
        end
      end
      return nil
    end

    -- Mock os.remove
    os.remove = function(path)
      if mock_files[path] then
        mock_files[path] = nil
        return true
      end
      return nil, "File not found"
    end

    -- Mock os.getenv
    os.getenv = function(name)
      if name == "CLAUDE_CONFIG_DIR" then
        return nil -- Use default directory
      end
      return original_os_getenv(name)
    end
  end

  local function restore_file_mocks()
    io.open = original_io_open
    os.remove = original_os_remove
    os.getenv = original_os_getenv
    mock_files = {}
  end

  before_each(function()
    package.loaded["claudecode.lockfile"] = nil
    setup_file_mocks()

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
    vim.lsp = {
      get_clients = function()
        return {}
      end,
    }

    lockfile = require("claudecode.lockfile")
  end)

  after_each(function()
    restore_file_mocks()
  end)

  describe("generate_auth_token", function()
    it("returns a string", function()
      local token = lockfile.generate_auth_token()
      assert.is_string(token)
    end)

    it("generates UUID with correct length", function()
      local token = lockfile.generate_auth_token()
      assert.equals(36, #token)
    end)

    it("generates UUID with correct format", function()
      local token = lockfile.generate_auth_token()
      -- UUID format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
      assert.is_truthy(token:match("^[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+$"))
    end)

    it("generates UUID with version 4 marker", function()
      local token = lockfile.generate_auth_token()
      -- The 13th character should be '4' (version 4)
      local parts = {}
      for part in token:gmatch("[^-]+") do
        table.insert(parts, part)
      end
      assert.equals(5, #parts)
      assert.equals("4", parts[3]:sub(1, 1))
    end)

    it("generates UUID with correct variant", function()
      local token = lockfile.generate_auth_token()
      local parts = {}
      for part in token:gmatch("[^-]+") do
        table.insert(parts, part)
      end
      -- The 17th character (first char of 4th section) should be 8, 9, a, or b
      local variant_char = parts[4]:sub(1, 1)
      assert.is_truthy(variant_char:match("[89ab]"))
    end)

    it("generates unique tokens", function()
      local tokens = {}
      for _ = 1, 100 do
        local token = lockfile.generate_auth_token()
        assert.is_falsy(tokens[token], "Duplicate token generated: " .. token)
        tokens[token] = true
      end
    end)

    it("generates lowercase hex characters", function()
      local token = lockfile.generate_auth_token()
      assert.equals(token:lower(), token)
    end)
  end)

  describe("create", function()
    it("creates lock file successfully", function()
      local success, path, token = lockfile.create(12345)
      assert.is_true(success)
      assert.is_string(path)
      assert.is_string(token)
    end)

    it("returns correct lock file path", function()
      local success, path = lockfile.create(12345)
      assert.is_true(success)
      assert.is_truthy(path:match("12345%.lock$"))
    end)

    it("creates valid JSON content", function()
      local success, path = lockfile.create(12345)
      assert.is_true(success)
      local content = mock_files[path]
      assert.is_string(content)
      local data = vim.json.decode(content)
      assert.is_table(data)
    end)

    it("includes pid in lock file", function()
      local success, path = lockfile.create(12345)
      assert.is_true(success)
      local data = vim.json.decode(mock_files[path])
      assert.equals(12345, data.pid)
    end)

    it("includes ideName in lock file", function()
      local success, path = lockfile.create(12345)
      assert.is_true(success)
      local data = vim.json.decode(mock_files[path])
      assert.equals("Neovim", data.ideName)
    end)

    it("includes transport type in lock file", function()
      local success, path = lockfile.create(12345)
      assert.is_true(success)
      local data = vim.json.decode(mock_files[path])
      assert.equals("ws", data.transport)
    end)

    it("includes auth token in lock file", function()
      local success, path = lockfile.create(12345)
      assert.is_true(success)
      local data = vim.json.decode(mock_files[path])
      assert.is_string(data.authToken)
      assert.equals(36, #data.authToken)
    end)

    it("includes workspace folders in lock file", function()
      local success, path = lockfile.create(12345)
      assert.is_true(success)
      local data = vim.json.decode(mock_files[path])
      assert.is_table(data.workspaceFolders)
    end)

    it("uses provided auth token", function()
      local custom_token = "custom-auth-token-12345678"
      local success, path, token = lockfile.create(12345, custom_token)
      assert.is_true(success)
      assert.equals(custom_token, token)
      local data = vim.json.decode(mock_files[path])
      assert.equals(custom_token, data.authToken)
    end)

    it("fails with nil port", function()
      local success, err = lockfile.create(nil)
      assert.is_false(success)
      assert.is_truthy(err:match("Invalid port"))
    end)

    it("fails with non-number port", function()
      local success, err = lockfile.create("12345")
      assert.is_false(success)
      assert.is_truthy(err:match("Invalid port"))
    end)

    it("fails with port below 1", function()
      local success, err = lockfile.create(0)
      assert.is_false(success)
      assert.is_truthy(err:match("out of valid range"))
    end)

    it("fails with port above 65535", function()
      local success, err = lockfile.create(65536)
      assert.is_false(success)
      assert.is_truthy(err:match("out of valid range"))
    end)

    it("accepts minimum valid port", function()
      local success = lockfile.create(1)
      assert.is_true(success)
    end)

    it("accepts maximum valid port", function()
      local success = lockfile.create(65535)
      assert.is_true(success)
    end)

    it("fails with non-string auth token", function()
      local success, err = lockfile.create(12345, 12345)
      assert.is_false(success)
      assert.is_truthy(err:match("must be a string"))
    end)

    it("fails with too short auth token", function()
      local success, err = lockfile.create(12345, "short")
      assert.is_false(success)
      assert.is_truthy(err:match("too short"))
    end)

    it("fails with too long auth token", function()
      local long_token = string.rep("x", 501)
      local success, err = lockfile.create(12345, long_token)
      assert.is_false(success)
      assert.is_truthy(err:match("too long"))
    end)

    it("accepts minimum length auth token", function()
      local success = lockfile.create(12345, "1234567890")
      assert.is_true(success)
    end)

    it("accepts maximum length auth token", function()
      local success = lockfile.create(12345, string.rep("x", 500))
      assert.is_true(success)
    end)
  end)

  describe("remove", function()
    it("removes existing lock file", function()
      -- First create a lock file
      local success, path = lockfile.create(12345)
      assert.is_true(success)
      assert.is_truthy(mock_files[path])

      -- Then remove it
      local remove_success = lockfile.remove(12345)
      assert.is_true(remove_success)
      assert.is_falsy(mock_files[path])
    end)

    it("fails with nil port", function()
      local success, err = lockfile.remove(nil)
      assert.is_false(success)
      assert.is_truthy(err:match("Invalid port"))
    end)

    it("fails with non-number port", function()
      local success, err = lockfile.remove("12345")
      assert.is_false(success)
      assert.is_truthy(err:match("Invalid port"))
    end)

    it("fails for non-existent lock file", function()
      local success, err = lockfile.remove(99999)
      assert.is_false(success)
      assert.is_truthy(err:match("does not exist"))
    end)
  end)

  describe("update", function()
    it("creates lock file if it doesn't exist", function()
      local success, path = lockfile.update(12345)
      assert.is_true(success)
      assert.is_truthy(mock_files[path])
    end)

    it("replaces existing lock file", function()
      -- Create initial lock file
      local success1, path1, token1 = lockfile.create(12345)
      assert.is_true(success1)

      -- Update should create new file with possibly different token
      local success2, path2 = lockfile.update(12345)
      assert.is_true(success2)
      assert.equals(path1, path2)
      assert.is_truthy(mock_files[path2])
    end)

    it("fails with nil port", function()
      local success, err = lockfile.update(nil)
      assert.is_false(success)
      assert.is_truthy(err:match("Invalid port"))
    end)

    it("fails with non-number port", function()
      local success, err = lockfile.update("12345")
      assert.is_false(success)
      assert.is_truthy(err:match("Invalid port"))
    end)
  end)

  describe("get_auth_token", function()
    it("reads auth token from existing lock file", function()
      -- Create lock file with known token
      local known_token = "known-test-token-123456"
      local success, path = lockfile.create(12345, known_token)
      assert.is_true(success)

      -- Read it back
      local read_success, token = lockfile.get_auth_token(12345)
      assert.is_true(read_success)
      assert.equals(known_token, token)
    end)

    it("fails with nil port", function()
      local success, token, err = lockfile.get_auth_token(nil)
      assert.is_false(success)
      assert.is_nil(token)
      assert.is_truthy(err:match("Invalid port"))
    end)

    it("fails with non-number port", function()
      local success, token, err = lockfile.get_auth_token("12345")
      assert.is_false(success)
      assert.is_nil(token)
      assert.is_truthy(err:match("Invalid port"))
    end)

    it("fails for non-existent lock file", function()
      local success, token, err = lockfile.get_auth_token(99999)
      assert.is_false(success)
      assert.is_nil(token)
      assert.is_truthy(err:match("does not exist"))
    end)

    it("fails for empty lock file", function()
      -- Manually create empty file
      local path = lockfile.lock_dir .. "/54321.lock"
      mock_files[path] = ""

      local success, token, err = lockfile.get_auth_token(54321)
      assert.is_false(success)
      assert.is_nil(token)
      assert.is_truthy(err:match("empty"))
    end)

    it("fails for invalid JSON", function()
      -- Manually create invalid JSON file
      local path = lockfile.lock_dir .. "/54321.lock"
      mock_files[path] = "not valid json"

      local success, token, err = lockfile.get_auth_token(54321)
      assert.is_false(success)
      assert.is_nil(token)
      assert.is_truthy(err:match("parse") or err:match("JSON"))
    end)

    it("fails for JSON without auth token", function()
      -- Manually create JSON without authToken
      local path = lockfile.lock_dir .. "/54321.lock"
      mock_files[path] = vim.json.encode({ pid = 12345, ideName = "Test" })

      local success, token, err = lockfile.get_auth_token(54321)
      assert.is_false(success)
      assert.is_nil(token)
      assert.is_truthy(err:match("auth token"))
    end)
  end)

  describe("get_workspace_folders", function()
    it("returns table", function()
      local folders = lockfile.get_workspace_folders()
      assert.is_table(folders)
    end)

    it("includes current working directory", function()
      local folders = lockfile.get_workspace_folders()
      local found_cwd = false
      for _, folder in ipairs(folders) do
        if folder == "/test/workspace" then
          found_cwd = true
          break
        end
      end
      assert.is_true(found_cwd)
    end)

    it("includes LSP workspace folders", function()
      -- Mock LSP client with workspace folders
      vim.lsp.get_clients = function()
        return {
          {
            config = {
              workspace_folders = {
                { uri = "file:///test/lsp/folder1" },
                { uri = "file:///test/lsp/folder2" },
              },
            },
          },
        }
      end

      local folders = lockfile.get_workspace_folders()
      local found_folder1 = false
      local found_folder2 = false
      for _, folder in ipairs(folders) do
        if folder == "/test/lsp/folder1" then
          found_folder1 = true
        end
        if folder == "/test/lsp/folder2" then
          found_folder2 = true
        end
      end
      assert.is_true(found_folder1)
      assert.is_true(found_folder2)
    end)

    it("deduplicates folders", function()
      vim.fn.getcwd = function()
        return "/test/workspace"
      end
      vim.lsp.get_clients = function()
        return {
          {
            config = {
              workspace_folders = {
                { uri = "file:///test/workspace" }, -- Same as cwd
              },
            },
          },
        }
      end

      local folders = lockfile.get_workspace_folders()
      local count = 0
      for _, folder in ipairs(folders) do
        if folder == "/test/workspace" then
          count = count + 1
        end
      end
      assert.equals(1, count)
    end)

    it("handles LSP client without workspace_folders", function()
      vim.lsp.get_clients = function()
        return {
          {
            config = {},
          },
        }
      end

      local folders = lockfile.get_workspace_folders()
      assert.is_table(folders)
      assert.is_true(#folders >= 1) -- At least cwd
    end)

    it("handles empty LSP clients", function()
      vim.lsp.get_clients = function()
        return {}
      end

      local folders = lockfile.get_workspace_folders()
      assert.is_table(folders)
      assert.is_true(#folders >= 1) -- At least cwd
    end)
  end)

  describe("lock_dir", function()
    it("uses default directory", function()
      assert.is_truthy(lockfile.lock_dir:match("%.claude/ide$"))
    end)

    it("respects CLAUDE_CONFIG_DIR environment variable", function()
      os.getenv = function(name)
        if name == "CLAUDE_CONFIG_DIR" then
          return "/custom/claude/config"
        end
        return original_os_getenv(name)
      end

      -- Re-require to pick up new env var
      package.loaded["claudecode.lockfile"] = nil
      local new_lockfile = require("claudecode.lockfile")
      assert.equals("/custom/claude/config/ide", new_lockfile.lock_dir)
    end)
  end)
end)
