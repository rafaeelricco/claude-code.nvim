--- Tool implementation for checking if a document is dirty.

--- Handles the checkDocumentDirty tool invocation.
-- Checks if the specified file (buffer) has unsaved changes.
-- @param params table The input parameters for the tool.
-- @field params.filePath string Path to the file to check.
-- @return table A table indicating if the document is dirty.
-- @error table A table with code, message, and data for JSON-RPC error if failed.
local function handler(params)
  if not params.filePath then
    error({ code = -32602, message = "Invalid params", data = "Missing filePath parameter" })
  end

  local bufnr = vim.fn.bufnr(params.filePath)

  if bufnr == -1 then
    -- It's debatable if this is an "error" or if it should return { isDirty = false }
    -- For now, treating as an operational error as the file isn't actively managed by a buffer.
    error({
      code = -32000,
      message = "File operation error",
      data = "File not open in editor: " .. params.filePath,
    })
  end

  local is_dirty = vim.api.nvim_buf_get_option(bufnr, "modified")

  return { isDirty = is_dirty }
end

return {
  name = "checkDocumentDirty",
  schema = nil, -- Internal tool
  handler = handler,
}
