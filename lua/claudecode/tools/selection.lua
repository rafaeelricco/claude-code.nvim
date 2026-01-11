---@brief [[
--- MCP Tool: getCurrentSelection
--- Returns the current text selection in Neovim
---@brief ]]

---@module 'claudecode.tools.selection'
local M = {}

local logger = require("claudecode.logger")

--- Get the current selection
---@param _params table Parameters (unused)
---@return table|nil result Selection result
---@return table|nil error Error if failed
local function handler(_params)
  -- Try to get the last visual selection
  local selection_module = require("claudecode.selection")
  local selection = selection_module.get_last_selection()

  if not selection then
    -- Try to get from visual marks
    selection = selection_module.get_visual_selection()
  end

  if not selection then
    logger.debug("tools.getCurrentSelection", "No selection available")
    local file_path = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    return {
      text = "",
      filePath = file_path,
      fileUrl = file_path ~= "" and ("file://" .. file_path) or "",
      selection = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 0, character = 0 },
        isEmpty = true,
      },
      content = {
        {
          type = "text",
          text = "",
        },
      },
    }, nil
  end

  logger.debug(
    "tools.getCurrentSelection",
    string.format("Returning selection: %d chars from %s", #selection.text, selection.file)
  )

  local mcp_selection = selection_module.to_mcp_selection(selection)
  if not mcp_selection then
    return nil, {
      code = -32000,
      message = "Failed to convert selection",
    }
  end

  mcp_selection.content = {
    {
      type = "text",
      text = mcp_selection.text,
    },
  }

  return mcp_selection, nil
end

--- Register the tool with the registry
---@param registry table The tool registry
function M.register(registry)
  registry.register({
    name = "getCurrentSelection",
    description = "Gets the current text selection in the editor",
    inputSchema = {
      type = "object",
      properties = {},
    },
    handler = handler,
  })
end

return M
