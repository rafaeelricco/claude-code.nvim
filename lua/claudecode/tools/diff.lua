---@brief [[
--- MCP Tool: openDiff
--- Opens a diff view comparing original file with proposed changes
---@brief ]]

---@module 'claudecode.tools.diff'
local M = {}

local logger = require("claudecode.logger")

--- Open a diff view
---@param params table Parameters { path: string, newContent: string }
---@return table|nil result Success result
---@return table|nil error Error if failed
local function handler(params)
  local path = params.path
  local new_content = params.newContent

  if not path or path == "" then
    return nil, {
      code = -32602,
      message = "Invalid params: path is required",
    }
  end

  if not new_content then
    return nil, {
      code = -32602,
      message = "Invalid params: newContent is required",
    }
  end

  -- Expand path
  path = vim.fn.expand(path)

  -- Schedule the diff opening on the main thread
  vim.schedule(function()
    local diff_module = require("claudecode.diff")
    local tab_name = path .. " (diff)"
    local result = diff_module.open_diff(path, path, new_content, tab_name)

    if not result.success then
      logger.error("tools.openDiff", "Failed to open diff for: " .. path .. " - " .. (result.error or "unknown error"))
    else
      logger.debug("tools.openDiff", "Opened diff for: " .. path)
    end
  end)

  return {
    content = {
      {
        type = "text",
        text = "Diff opened for: " .. path,
      },
    },
  }, nil
end

--- Register the tool with the registry
---@param registry table The tool registry
function M.register(registry)
  registry.register({
    name = "openDiff",
    description = "Opens a diff view comparing the original file with proposed changes",
    inputSchema = {
      type = "object",
      properties = {
        path = {
          type = "string",
          description = "The path to the file to diff",
        },
        newContent = {
          type = "string",
          description = "The proposed new content for the file",
        },
      },
      required = { "path", "newContent" },
    },
    handler = handler,
  })
end

return M
