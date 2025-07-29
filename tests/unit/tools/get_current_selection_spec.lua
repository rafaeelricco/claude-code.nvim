require("tests.busted_setup") -- Ensure test helpers are loaded

describe("Tool: get_current_selection", function()
  local get_current_selection_handler
  local mock_selection_module

  before_each(function()
    -- Mock the selection module
    mock_selection_module = {
      get_latest_selection = spy.new(function()
        -- Default behavior: no selection
        return nil
      end),
    }
    package.loaded["claudecode.selection"] = mock_selection_module

    -- Reset and require the module under test
    package.loaded["claudecode.tools.get_current_selection"] = nil
    get_current_selection_handler = require("claudecode.tools.get_current_selection").handler

    -- Mock vim.api functions that might be called by the fallback if no selection
    _G.vim = _G.vim or {}
    _G.vim.api = _G.vim.api or {}
    _G.vim.api.nvim_get_current_buf = spy.new(function()
      return 1
    end)
    _G.vim.api.nvim_buf_get_name = spy.new(function(bufnr)
      if bufnr == 1 then
        return "/current/file.lua"
      end
      return "unknown_buffer"
    end)
  end)

  after_each(function()
    package.loaded["claudecode.selection"] = nil
    package.loaded["claudecode.tools.get_current_selection"] = nil
    _G.vim.api.nvim_get_current_buf = nil
    _G.vim.api.nvim_buf_get_name = nil
  end)

  it("should return an empty selection structure if no selection is available", function()
    mock_selection_module.get_latest_selection = spy.new(function()
      return nil
    end)

    local success, result = pcall(get_current_selection_handler, {})
    expect(success).to_be_true()
    expect(result).to_be_table()
    expect(result.text).to_be("")
    expect(result.filePath).to_be("/current/file.lua")
    expect(result.selection.isEmpty).to_be_true()
    expect(result.selection.start.line).to_be(0) -- Default empty selection
    expect(result.selection.start.character).to_be(0)
    assert.spy(mock_selection_module.get_latest_selection).was_called()
  end)

  it("should return the selection data from claudecode.selection if available", function()
    local mock_sel_data = {
      text = "selected text",
      filePath = "/path/to/file.lua",
      fileUrl = "file:///path/to/file.lua",
      selection = {
        start = { line = 10, character = 4 },
        ["end"] = { line = 10, character = 17 },
        isEmpty = false,
      },
    }
    mock_selection_module.get_latest_selection = spy.new(function()
      return mock_sel_data
    end)

    local success, result = pcall(get_current_selection_handler, {})
    expect(success).to_be_true()
    expect(result).to_be_table()
    assert.are.same(mock_sel_data, result) -- Should return the exact table
    assert.spy(mock_selection_module.get_latest_selection).was_called()
  end)

  it("should handle pcall failure when requiring selection module", function()
    -- Simulate require failing
    package.loaded["claudecode.selection"] = nil -- Ensure it's not cached
    local original_require = _G.require
    _G.require = function(mod_name)
      if mod_name == "claudecode.selection" then
        error("Simulated require failure for claudecode.selection")
      end
      return original_require(mod_name)
    end

    local success, err = pcall(get_current_selection_handler, {})
    _G.require = original_require -- Restore original require

    expect(success).to_be_false()
    expect(err).to_be_table()
    expect(err.code).to_be(-32000)
    assert_contains(err.message, "Internal server error")
    assert_contains(err.data, "Failed to load selection module")
  end)
end)
