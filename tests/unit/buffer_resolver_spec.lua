--- Tests for lua/claudecode/buffer_resolver.lua
--- Non-file buffer resolution: marker stripping, path resolution, materialize, pipeline order

-- Setup mock vim if not in Neovim
if not vim then
  require("tests.helpers.mock_vim").setup()
end

describe("buffer_resolver", function()
  local resolver

  before_each(function()
    package.loaded["claudecode.buffer_resolver"] = nil
    resolver = require("claudecode.buffer_resolver")
  end)

  describe("strip_markers", function()
    it("extracts path from a neogit 'modified:' line", function()
      assert.equals("lua/claudecode/init.lua", resolver._strip_markers("modified:   lua/claudecode/init.lua"))
    end)

    it("extracts path from a git status flag line", function()
      assert.equals("lua/foo.lua", resolver._strip_markers("M  lua/foo.lua"))
    end)

    it("extracts the b/ path from a diff +++ line", function()
      assert.equals("lua/foo.lua", resolver._strip_markers("+++ b/lua/foo.lua"))
    end)

    it("keeps the old path on a rename line", function()
      assert.equals("lua/old.lua", resolver._strip_markers("renamed: lua/old.lua -> lua/new.lua"))
    end)

    it("returns nil when no path-ish token is present", function()
      assert.is_nil(resolver._strip_markers("Unstaged changes (3)"))
    end)
  end)

  describe("to_readable", function()
    it("returns nil for a non-readable token", function()
      assert.is_nil(resolver._to_readable("does/not/exist-xyz.lua", vim.fn.getcwd()))
    end)

    it("joins root and resolves a real file to an absolute path", function()
      local root = vim.fn.getcwd()
      local abs = resolver._to_readable("lua/claudecode/buffer_resolver.lua", root)
      assert.is_not_nil(abs)
      assert.equals(1, vim.fn.filereadable(abs))
      assert.equals("/", abs:sub(1, 1))
    end)
  end)

  describe("dedup", function()
    it("removes duplicates, preserving first-seen order", function()
      local out = resolver._dedup({ "a", "b", "a", "c", "b" })
      assert.same({ "a", "b", "c" }, out)
    end)
  end)

  describe("materialize", function()
    it("writes the buffer text to a scratch file and returns its path", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line one", "line two", "line three" })

      local path = resolver.materialize({ bufnr = buf })
      assert.is_not_nil(path)
      assert.equals(1, vim.fn.filereadable(path))
      assert.same({ "line one", "line two", "line three" }, vim.fn.readfile(path))

      vim.fn.delete(path)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("writes only the requested range", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "b", "c", "d" })

      local path = resolver.materialize({ bufnr = buf, line1 = 2, line2 = 3 })
      assert.same({ "b", "c" }, vim.fn.readfile(path))

      vim.fn.delete(path)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("resolve", function()
    it("returns an error when disabled via config", function()
      local claudecode = require("claudecode")
      local saved = claudecode.state.config
      claudecode.state.config = { buffer_resolver = { enabled = false } }

      local result = resolver.resolve({ bufnr = vim.api.nvim_get_current_buf() })
      assert.equals(0, #result.paths)
      assert.is_not_nil(result.error)

      claudecode.state.config = saved
    end)

    it("falls back to materialize when no real file resolves", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Unstaged changes (0)", "nothing here" })

      local result = resolver.resolve({ bufnr = buf })
      assert.equals("materialize", result.source)
      assert.equals(1, #result.paths)
      assert.equals(1, vim.fn.filereadable(result.paths[1]))

      vim.fn.delete(result.paths[1])
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("resolves real paths via line-parse before materializing", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "modified: lua/claudecode/buffer_resolver.lua" })

      local result = resolver.resolve({ bufnr = buf, line1 = 1, line2 = 1 })
      -- a real file resolved => not materialized; path points at the referenced file
      assert.equals(1, #result.paths)
      assert.matches("buffer_resolver%.lua$", result.paths[1])

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
