---@brief [[
--- Headless Claude Code Neovim integration.
--- Provides a local WebSocket MCP server and lock file discovery for Claude CLI.
---@brief ]]

---@module 'claudecode'
local M = {}

local config_module = require("claudecode.config")
local logger = require("claudecode.logger")

--- @class ClaudeCode.Version
--- @field major integer Major version number
--- @field minor integer Minor version number
--- @field patch integer Patch version number
--- @field prerelease string|nil Prerelease identifier
--- @field string fun(self: ClaudeCode.Version):string Returns the formatted version string

--- @type ClaudeCode.Version
M.version = {
  major = 0,
  minor = 2,
  patch = 0,
  prerelease = nil,
  string = function(self)
    local version = string.format("%d.%d.%d", self.major, self.minor, self.patch)
    if self.prerelease then
      version = version .. "-" .. self.prerelease
    end
    return version
  end,
}

--- @class ClaudeCode.Config
--- @field port_range {min: integer, max: integer} Port range for WebSocket server.
--- @field auto_start boolean Auto-start WebSocket server on Neovim startup.
--- @field log_level "trace"|"debug"|"info"|"warn"|"error" Log level.

--- @class ClaudeCode.State
--- @field config ClaudeCode.Config The current plugin configuration.
--- @field server table|nil The WebSocket server module.
--- @field port number|nil The port the server is running on.
--- @field auth_token string|nil The authentication token for the current session.
--- @field initialized boolean Whether the plugin has been initialized.

--- @type ClaudeCode.State
M.state = {
  config = vim.deepcopy(config_module.defaults),
  server = nil,
  port = nil,
  auth_token = nil,
  initialized = false,
}

---@brief Check if Claude Code is connected to the WebSocket server.
---@return boolean connected
function M.is_claude_connected()
  if not M.state.server then
    return false
  end

  local server_module = require("claudecode.server.init")
  local status = server_module.get_status()
  return status.running and status.client_count > 0
end

--- Set up the plugin with user configuration.
---@param opts ClaudeCode.Config|nil
---@return table
function M.setup(opts)
  M.state.config = config_module.apply(opts or {})
  logger.setup(M.state.config)

  if M.state.config.auto_start then
    M.start(false)
  end

  M._create_commands()

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("ClaudeCodeShutdown", { clear = true }),
    callback = function()
      if M.state.server then
        M.stop()
      end
    end,
    desc = "Automatically stop Claude Code integration when exiting Neovim",
  })

  M.state.initialized = true
  return M
end

--- Start the Claude Code integration.
---@param show_startup_notification? boolean
---@return boolean success
---@return number|string port_or_error
function M.start(show_startup_notification)
  if show_startup_notification == nil then
    show_startup_notification = true
  end

  if M.state.server then
    local msg = "Claude Code integration is already running on port " .. tostring(M.state.port)
    logger.warn("init", msg)
    return false, "Already running"
  end

  local server = require("claudecode.server.init")
  local lockfile = require("claudecode.lockfile")

  local auth_success, auth_token = pcall(lockfile.generate_auth_token)
  if not auth_success then
    local error_msg = "Failed to generate authentication token: " .. (auth_token or "unknown error")
    logger.error("init", error_msg)
    return false, error_msg
  end

  if type(auth_token) ~= "string" or #auth_token < 10 then
    local error_msg = "Invalid authentication token generated"
    logger.error("init", error_msg)
    return false, error_msg
  end

  local success, result = server.start(M.state.config, auth_token)
  if not success then
    local error_msg = "Failed to start Claude Code server: " .. (result or "unknown error")
    logger.error("init", error_msg)
    return false, error_msg
  end

  M.state.server = server
  M.state.port = tonumber(result)
  M.state.auth_token = auth_token

  local lock_success, lock_result, returned_auth_token = lockfile.create(M.state.port, auth_token)
  if not lock_success then
    server.stop()
    M.state.server = nil
    M.state.port = nil
    M.state.auth_token = nil

    local error_msg = "Failed to create lock file: " .. (lock_result or "unknown error")
    logger.error("init", error_msg)
    return false, error_msg
  end

  if returned_auth_token ~= auth_token then
    server.stop()
    M.state.server = nil
    M.state.port = nil
    M.state.auth_token = nil

    local error_msg = "Authentication token mismatch between server and lock file"
    logger.error("init", error_msg)
    return false, error_msg
  end

  if show_startup_notification then
    logger.info("init", "Claude Code integration started on port " .. tostring(M.state.port))
  end

  return true, M.state.port
end

--- Stop the Claude Code integration.
---@return boolean success
---@return string? error
function M.stop()
  if not M.state.server then
    logger.warn("init", "Claude Code integration is not running")
    return false, "Not running"
  end

  local lockfile = require("claudecode.lockfile")
  local lock_success, lock_error = lockfile.remove(M.state.port)
  if not lock_success then
    logger.warn("init", "Failed to remove lock file: " .. lock_error)
  end

  local success, error = M.state.server.stop()
  if not success then
    logger.error("init", "Failed to stop Claude Code integration: " .. error)
    return false, error
  end

  M.state.server = nil
  M.state.port = nil
  M.state.auth_token = nil

  logger.info("init", "Claude Code integration stopped")
  return true
end

---@private
function M._create_commands()
  local function disabled_command(name)
    return function()
      logger.warn("command", name .. " is disabled in the headless build")
    end
  end

  vim.api.nvim_create_user_command("ClaudeCodeStart", function()
    M.start()
  end, {
    desc = "Start Claude Code integration",
  })

  vim.api.nvim_create_user_command("ClaudeCodeStop", function()
    M.stop()
  end, {
    desc = "Stop Claude Code integration",
  })

  vim.api.nvim_create_user_command("ClaudeCodeStatus", function()
    if M.state.server and M.state.port then
      logger.info("command", "Claude Code integration is running on port " .. tostring(M.state.port))
    else
      logger.info("command", "Claude Code integration is not running")
    end
  end, {
    desc = "Show Claude Code integration status",
  })

  vim.api.nvim_create_user_command("ClaudeCode", disabled_command("ClaudeCode"), { nargs = "*" })
  vim.api.nvim_create_user_command("ClaudeCodeFocus", disabled_command("ClaudeCodeFocus"), { nargs = "*" })
  vim.api.nvim_create_user_command("ClaudeCodeOpen", disabled_command("ClaudeCodeOpen"), { nargs = "*" })
  vim.api.nvim_create_user_command("ClaudeCodeClose", disabled_command("ClaudeCodeClose"), {})
  vim.api.nvim_create_user_command("ClaudeCodeSend", disabled_command("ClaudeCodeSend"), { range = true })
  vim.api.nvim_create_user_command("ClaudeCodeAdd", disabled_command("ClaudeCodeAdd"), {
    nargs = "*",
    complete = "file",
  })
  vim.api.nvim_create_user_command("ClaudeCodeTreeAdd", disabled_command("ClaudeCodeTreeAdd"), {})
  vim.api.nvim_create_user_command("ClaudeCodeDiffAccept", disabled_command("ClaudeCodeDiffAccept"), {})
  vim.api.nvim_create_user_command("ClaudeCodeDiffDeny", disabled_command("ClaudeCodeDiffDeny"), {})
end

--- Get version information.
---@return table
function M.get_version()
  return {
    version = M.version:string(),
    major = M.version.major,
    minor = M.version.minor,
    patch = M.version.patch,
    prerelease = M.version.prerelease,
  }
end

---@return boolean
function M.is_running()
  return M.state.server ~= nil
end

---@return number|nil
function M.get_port()
  return M.state.port
end

return M
