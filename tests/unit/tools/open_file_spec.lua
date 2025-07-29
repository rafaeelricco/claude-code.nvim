require("tests.busted_setup") -- Ensure test helpers are loaded

describe("Tool: open_file", function()
  local open_file_handler

  before_each(function()
    -- Reset mocks and require the module under test
    package.loaded["claudecode.tools.open_file"] = nil
    open_file_handler = require("claudecode.tools.open_file").handler

    -- Mock Neovim functions used by the handler
    _G.vim = _G.vim or {}
    _G.vim.fn = _G.vim.fn or {}
    _G.vim.api = _G.vim.api or {}
    _G.vim.cmd_history = {} -- Store cmd history for assertions
    _G.vim.fn.expand = spy.new(function(path)
      return path -- Simple pass-through for testing
    end)
    _G.vim.fn.filereadable = spy.new(function(path)
      if path == "non_readable_file.txt" then
        return 0
      end
      return 1 -- Assume readable by default for other paths
    end)
    _G.vim.fn.fnameescape = spy.new(function(path)
      return path -- Simple pass-through
    end)
    _G.vim.cmd = spy.new(function(command)
      table.insert(_G.vim.cmd_history, command)
    end)

    -- Mock window-related APIs
    _G.vim.api.nvim_list_wins = spy.new(function()
      return { 1000 } -- Return a single window
    end)
    _G.vim.api.nvim_win_get_buf = spy.new(function(win)
      return 1 -- Mock buffer ID
    end)
    _G.vim.api.nvim_buf_get_option = spy.new(function(buf, option)
      return "" -- Return empty string for all options
    end)
    _G.vim.api.nvim_win_get_config = spy.new(function(win)
      return {} -- Return empty config (no relative positioning)
    end)
    _G.vim.api.nvim_win_call = spy.new(function(win, callback)
      return callback() -- Just execute the callback
    end)
    _G.vim.api.nvim_set_current_win = spy.new(function(win)
      -- Do nothing
    end)
    _G.vim.api.nvim_get_current_win = spy.new(function()
      return 1000
    end)
  end)

  after_each(function()
    -- Clean up global mocks if necessary, though spy.restore() is better if using full spy.lua
    _G.vim.fn.expand = nil
    _G.vim.fn.filereadable = nil
    _G.vim.fn.fnameescape = nil
    _G.vim.cmd = nil
    _G.vim.cmd_history = nil
  end)

  it("should error if filePath parameter is missing", function()
    local success, err = pcall(open_file_handler, {})
    expect(success).to_be_false()
    expect(err).to_be_table()
    expect(err.code).to_be(-32602) -- Invalid params
    assert_contains(err.message, "Invalid params")
    assert_contains(err.data, "Missing filePath parameter")
  end)

  it("should error if file is not readable", function()
    local params = { filePath = "non_readable_file.txt" }
    local success, err = pcall(open_file_handler, params)
    expect(success).to_be_false()
    expect(err).to_be_table()
    expect(err.code).to_be(-32000) -- File operation error
    assert_contains(err.message, "File operation error")
    assert_contains(err.data, "File not found: non_readable_file.txt")
    assert.spy(_G.vim.fn.expand).was_called_with("non_readable_file.txt")
    assert.spy(_G.vim.fn.filereadable).was_called_with("non_readable_file.txt")
  end)

  it("should call vim.cmd with edit and the escaped file path on success", function()
    local params = { filePath = "readable_file.txt" }
    local success, result = pcall(open_file_handler, params)

    expect(success).to_be_true()
    expect(result).to_be_table()
    expect(result.message).to_be("File opened: readable_file.txt")

    assert.spy(_G.vim.fn.expand).was_called_with("readable_file.txt")
    assert.spy(_G.vim.fn.filereadable).was_called_with("readable_file.txt")
    assert.spy(_G.vim.fn.fnameescape).was_called_with("readable_file.txt")

    expect(#_G.vim.cmd_history).to_be(1)
    expect(_G.vim.cmd_history[1]).to_be("edit readable_file.txt")
  end)

  it("should handle filePath needing expansion", function()
    _G.vim.fn.expand = spy.new(function(path)
      if path == "~/.config/nvim/init.lua" then
        return "/Users/testuser/.config/nvim/init.lua"
      end
      return path
    end)
    local params = { filePath = "~/.config/nvim/init.lua" }
    local success, result = pcall(open_file_handler, params)

    expect(success).to_be_true()
    expect(result.message).to_be("File opened: /Users/testuser/.config/nvim/init.lua")
    assert.spy(_G.vim.fn.expand).was_called_with("~/.config/nvim/init.lua")
    assert.spy(_G.vim.fn.filereadable).was_called_with("/Users/testuser/.config/nvim/init.lua")
    assert.spy(_G.vim.fn.fnameescape).was_called_with("/Users/testuser/.config/nvim/init.lua")
    expect(_G.vim.cmd_history[1]).to_be("edit /Users/testuser/.config/nvim/init.lua")
  end)

  -- TODO: Add tests for selection by line numbers (params.startLine, params.endLine)
  -- This will require mocking vim.api.nvim_win_set_cursor or similar for selection
  -- and potentially vim.api.nvim_buf_get_lines if text content matters for selection.

  -- TODO: Add tests for selection by text patterns (params.startText, params.endText)
  -- This will require more complex mocking of buffer content and search functions.
end)
