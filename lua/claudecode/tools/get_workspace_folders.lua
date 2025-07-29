--- Tool implementation for getting workspace folders.

--- Handles the getWorkspaceFolders tool invocation.
-- Retrieves workspace folders, currently defaulting to CWD and attempting LSP integration.
-- @param _params table The input parameters for the tool (currently unused).
-- @return table A table containing the list of workspace folders.
local function handler(_params) -- Prefix unused params with underscore
  local cwd = vim.fn.getcwd()

  -- TODO: Enhance integration with LSP workspace folders if available,
  -- similar to how it's done in claudecode.lockfile.get_workspace_folders.
  -- For now, this is a simplified version as per the original tool's direct implementation.

  local folders = {
    {
      name = vim.fn.fnamemodify(cwd, ":t"),
      uri = "file://" .. cwd,
      path = cwd,
    },
  }

  -- A more complete version would replicate the logic from claudecode.lockfile:
  -- local lsp_folders = get_lsp_workspace_folders_logic_here()
  -- for _, folder_path in ipairs(lsp_folders) do
  --   local already_exists = false
  --   for _, existing_folder in ipairs(folders) do
  --     if existing_folder.path == folder_path then
  --       already_exists = true
  --       break
  --     end
  --   end
  --   if not already_exists then
  --     table.insert(folders, {
  --       name = vim.fn.fnamemodify(folder_path, ":t"),
  --       uri = "file://" .. folder_path,
  --       path = folder_path,
  --     })
  --   end
  -- end

  return { workspaceFolders = folders }
end

return {
  name = "getWorkspaceFolders",
  schema = nil, -- Internal tool
  handler = handler,
}
