require("tests.busted_setup") -- Ensure test helpers are loaded

describe("Tool: get_open_editors", function()
  local get_open_editors_handler

  before_each(function()
    package.loaded["claudecode.tools.get_open_editors"] = nil
    get_open_editors_handler = require("claudecode.tools.get_open_editors").handler

    _G.vim = _G.vim or {}
    _G.vim.api = _G.vim.api or {}
    _G.vim.fn = _G.vim.fn or {}

    -- Default mocks
    _G.vim.api.nvim_list_bufs = spy.new(function()
      return {}
    end)
    _G.vim.api.nvim_buf_is_loaded = spy.new(function()
      return false
    end)
    _G.vim.fn.buflisted = spy.new(function()
      return 0
    end)
    _G.vim.api.nvim_buf_get_name = spy.new(function()
      return ""
    end)
    _G.vim.api.nvim_buf_get_option = spy.new(function()
      return false
    end)
  end)

  after_each(function()
    package.loaded["claudecode.tools.get_open_editors"] = nil
    -- Clear mocks
    _G.vim.api.nvim_list_bufs = nil
    _G.vim.api.nvim_buf_is_loaded = nil
    _G.vim.fn.buflisted = nil
    _G.vim.api.nvim_buf_get_name = nil
    _G.vim.api.nvim_buf_get_option = nil
  end)

  it("should return an empty list if no listed buffers are found", function()
    local success, result = pcall(get_open_editors_handler, {})
    expect(success).to_be_true()
    expect(result).to_be_table()
    expect(result.editors).to_be_table()
    expect(#result.editors).to_be(0)
  end)

  it("should return a list of open and listed editors", function()
    -- Ensure fresh api and fn tables for this specific test's mocks
    _G.vim.api = {} -- Keep api mock specific to this test's needs
    _G.vim.fn = { ---@type vim_fn_table
      -- Add common stubs, buflisted will be spied below
      mode = function()
        return "n"
      end,
      delete = function(_, _)
        return 0
      end,
      filereadable = function(_)
        return 1
      end,
      fnamemodify = function(fname, _)
        return fname
      end,
      expand = function(s, _)
        return s
      end,
      getcwd = function()
        return "/mock/cwd"
      end,
      mkdir = function(_, _, _)
        return 1
      end,
      buflisted = function(_)
        return 1
      end, -- Stub for type, will be spied
      -- buflisted will be spied
      bufname = function(_)
        return "mockbuffer"
      end,
      bufnr = function(_)
        return 1
      end,
      win_getid = function()
        return 1
      end,
      win_gotoid = function(_)
        return true
      end,
      line = function(_)
        return 1
      end,
      col = function(_)
        return 1
      end,
      virtcol = function(_)
        return 1
      end,
      getpos = function(_)
        return { 0, 1, 1, 0 }
      end,
      setpos = function(_, _)
        return true
      end,
      tempname = function()
        return "/tmp/mocktemp"
      end,
      globpath = function(_, _)
        return ""
      end,
      stdpath = function(_)
        return "/mock/stdpath"
      end,
      json_encode = function(_)
        return "{}"
      end,
      json_decode = function(_)
        return {}
      end,
      termopen = function(_, _)
        return 0
      end,
    }

    _G.vim.api.nvim_list_bufs = spy.new(function()
      return { 1, 2, 3 }
    end)
    _G.vim.api.nvim_buf_is_loaded = spy.new(function(bufnr)
      return bufnr == 1 or bufnr == 2 -- Buffer 3 is not loaded
    end)
    _G.vim.fn.buflisted = spy.new(function(bufnr)
      -- The handler checks `vim.fn.buflisted(bufnr) == 1`
      if bufnr == 1 or bufnr == 2 then
        return 1
      end
      return 0 -- Buffer 3 not listed
    end)
    _G.vim.api.nvim_buf_get_name = spy.new(function(bufnr)
      if bufnr == 1 then
        return "/path/to/file1.lua"
      end
      if bufnr == 2 then
        return "/path/to/file2.txt"
      end
      return ""
    end)
    _G.vim.api.nvim_buf_get_option = spy.new(function(bufnr, opt_name)
      if opt_name == "modified" then
        return bufnr == 2 -- file2.txt is dirty
      end
      return false
    end)

    local success, result = pcall(get_open_editors_handler, {})
    expect(success).to_be_true()
    expect(result.editors).to_be_table()
    expect(#result.editors).to_be(2)

    expect(result.editors[1].filePath).to_be("/path/to/file1.lua")
    expect(result.editors[1].fileUrl).to_be("file:///path/to/file1.lua")
    expect(result.editors[1].isDirty).to_be_false()

    expect(result.editors[2].filePath).to_be("/path/to/file2.txt")
    expect(result.editors[2].fileUrl).to_be("file:///path/to/file2.txt")
    expect(result.editors[2].isDirty).to_be_true()
  end)

  it("should filter out buffers that are not loaded", function()
    _G.vim.api.nvim_list_bufs = spy.new(function()
      return { 1 }
    end)
    _G.vim.api.nvim_buf_is_loaded = spy.new(function()
      return false
    end) -- Not loaded
    _G.vim.fn.buflisted = spy.new(function()
      return 1
    end)
    _G.vim.api.nvim_buf_get_name = spy.new(function()
      return "/path/to/file1.lua"
    end)

    local success, result = pcall(get_open_editors_handler, {})
    expect(success).to_be_true()
    expect(#result.editors).to_be(0)
  end)

  it("should filter out buffers that are not listed", function()
    _G.vim.api.nvim_list_bufs = spy.new(function()
      return { 1 }
    end)
    _G.vim.api.nvim_buf_is_loaded = spy.new(function()
      return true
    end)
    _G.vim.fn.buflisted = spy.new(function()
      return 0
    end) -- Not listed
    _G.vim.api.nvim_buf_get_name = spy.new(function()
      return "/path/to/file1.lua"
    end)

    local success, result = pcall(get_open_editors_handler, {})
    expect(success).to_be_true()
    expect(#result.editors).to_be(0)
  end)

  it("should filter out buffers with no file path", function()
    _G.vim.api.nvim_list_bufs = spy.new(function()
      return { 1 }
    end)
    _G.vim.api.nvim_buf_is_loaded = spy.new(function()
      return true
    end)
    _G.vim.fn.buflisted = spy.new(function()
      return 1
    end)
    _G.vim.api.nvim_buf_get_name = spy.new(function()
      return ""
    end) -- Empty path

    local success, result = pcall(get_open_editors_handler, {})
    expect(success).to_be_true()
    expect(#result.editors).to_be(0)
  end)
end)
