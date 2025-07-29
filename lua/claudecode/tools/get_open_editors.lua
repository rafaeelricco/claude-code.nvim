--- Tool implementation for getting a list of open editors.

local schema = {
  description = "Get list of currently open files",
  inputSchema = {
    type = "object",
    additionalProperties = false,
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
  },
}

--- Handles the getOpenEditors tool invocation.
-- Gets a list of currently open and listed files in Neovim.
-- @param _params table The input parameters for the tool (currently unused).
-- @return table A list of open editor information.
local function handler(_params) -- Prefix unused params with underscore
  local editors = {}
  local buffers = vim.api.nvim_list_bufs()

  for _, bufnr in ipairs(buffers) do
    -- Only include loaded, listed buffers with a file path
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.fn.buflisted(bufnr) == 1 then
      local file_path = vim.api.nvim_buf_get_name(bufnr)

      if file_path and file_path ~= "" then
        table.insert(editors, {
          filePath = file_path,
          fileUrl = "file://" .. file_path,
          isDirty = vim.api.nvim_buf_get_option(bufnr, "modified"),
        })
      end
    end
  end

  -- The MCP spec for tools/list implies the result should be the direct data.
  -- The 'content' and 'isError' fields were an internal convention that is
  -- now handled by the main M.handle_invoke in tools/init.lua.
  return { editors = editors }
end

return {
  name = "getOpenEditors",
  schema = schema,
  handler = handler,
}
