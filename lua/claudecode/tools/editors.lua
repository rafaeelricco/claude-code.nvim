---@brief [[
--- MCP Tool: getOpenEditors
--- Returns list of currently open files in Neovim
---@brief ]]

---@module 'claudecode.tools.editors'
local M = {}

local logger = require("claudecode.logger")

--- Get list of open editors/buffers
---@param _params table Parameters (unused)
---@return table|nil result List of open files
---@return table|nil error Error if failed
local function handler(_params)
  local editors = {}

  -- Get all buffers
  local buffers = vim.api.nvim_list_bufs()

  for _, buf in ipairs(buffers) do
    -- Only include loaded, listed buffers with a file name
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
      local name = vim.api.nvim_buf_get_name(buf)

      -- Skip unnamed buffers and special buffers
      if name ~= "" and not name:match("^term://") and not name:match("^%[") then
        local modified = vim.bo[buf].modified
        local is_active = buf == vim.api.nvim_get_current_buf()

        table.insert(editors, {
          filePath = name,
          fileUrl = "file://" .. name,
          isDirty = modified,
          isActive = is_active,
          -- Compatibility fields for newer clients
          path = name,
          isModified = modified,
        })
      end
    end
  end

  logger.debug("tools.getOpenEditors", "Found " .. #editors .. " open files")

  return {
    content = {
      {
        type = "text",
        text = vim.json.encode(editors),
      },
    },
    editors = editors,
  }, nil
end

--- Register the tool with the registry
---@param registry table The tool registry
function M.register(registry)
  registry.register({
    name = "getOpenEditors",
    description = "Gets the list of currently open files in the editor",
    inputSchema = {
      type = "object",
      properties = {},
    },
    handler = handler,
  })
end

return M
