require("tests.busted_setup") -- Ensure test helpers are loaded

describe("Tool: get_workspace_folders", function()
  local get_workspace_folders_handler

  before_each(function()
    package.loaded["claudecode.tools.get_workspace_folders"] = nil
    get_workspace_folders_handler = require("claudecode.tools.get_workspace_folders").handler

    _G.vim = _G.vim or {}
    _G.vim.fn = _G.vim.fn or {}

    -- Default mocks
    _G.vim.fn.getcwd = spy.new(function()
      return "/mock/project/root"
    end)
    _G.vim.fn.fnamemodify = spy.new(function(path, mod)
      if mod == ":t" then
        local parts = {}
        for part in string.gmatch(path, "[^/]+") do
          table.insert(parts, part)
        end
        return parts[#parts] or ""
      end
      return path
    end)
  end)

  after_each(function()
    package.loaded["claudecode.tools.get_workspace_folders"] = nil
    _G.vim.fn.getcwd = nil
    _G.vim.fn.fnamemodify = nil
  end)

  it("should return the current working directory as the only workspace folder", function()
    local success, result = pcall(get_workspace_folders_handler, {})
    expect(success).to_be_true()
    expect(result).to_be_table()
    expect(result.workspaceFolders).to_be_table()
    expect(#result.workspaceFolders).to_be(1)

    local folder = result.workspaceFolders[1]
    expect(folder.name).to_be("root")
    expect(folder.uri).to_be("file:///mock/project/root")
    expect(folder.path).to_be("/mock/project/root")

    assert.spy(_G.vim.fn.getcwd).was_called()
    assert.spy(_G.vim.fn.fnamemodify).was_called_with("/mock/project/root", ":t")
  end)

  it("should handle different CWD paths correctly", function()
    _G.vim.fn.getcwd = spy.new(function()
      return "/another/path/project_name"
    end)
    local success, result = pcall(get_workspace_folders_handler, {})
    expect(success).to_be_true()
    expect(#result.workspaceFolders).to_be(1)
    local folder = result.workspaceFolders[1]
    expect(folder.name).to_be("project_name")
    expect(folder.uri).to_be("file:///another/path/project_name")
    expect(folder.path).to_be("/another/path/project_name")
  end)

  -- TODO: Add tests when LSP workspace folder integration is implemented in the tool.
  -- This would involve mocking vim.lsp.get_clients() and its return structure.
end)
