--- Manages configuration for the headless Claude Code Neovim integration.
local M = {}

M.defaults = {
  port_range = { min = 10000, max = 65535 },
  auto_start = true,
  log_level = "info",
}

--- Validates the provided configuration table.
---@param config table
---@return boolean
function M.validate(config)
  assert(
    type(config.port_range) == "table"
      and type(config.port_range.min) == "number"
      and type(config.port_range.max) == "number"
      and config.port_range.min > 0
      and config.port_range.max <= 65535
      and config.port_range.min <= config.port_range.max,
    "Invalid port range"
  )

  assert(type(config.auto_start) == "boolean", "auto_start must be a boolean")

  local valid_log_levels = { "trace", "debug", "info", "warn", "error" }
  local is_valid_log_level = false
  for _, level in ipairs(valid_log_levels) do
    if config.log_level == level then
      is_valid_log_level = true
      break
    end
  end
  assert(is_valid_log_level, "log_level must be one of: " .. table.concat(valid_log_levels, ", "))

  return true
end

--- Applies user configuration on top of default settings and validates the result.
---@param user_config table|nil
---@return table
function M.apply(user_config)
  local config = vim.deepcopy(M.defaults)

  if user_config then
    for key, value in pairs(user_config) do
      if M.defaults[key] ~= nil then
        if type(M.defaults[key]) == "table" and type(value) == "table" then
          config[key] = vim.tbl_deep_extend("force", config[key], value)
        else
          config[key] = value
        end
      end
    end
  end

  M.validate(config)

  return config
end

return M
