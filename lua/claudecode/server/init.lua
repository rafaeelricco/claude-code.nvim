---@brief WebSocket server for headless Claude Code Neovim integration.
local claudecode_main = require("claudecode")
local logger = require("claudecode.logger")
local tcp_server = require("claudecode.server.tcp")

local MCP_PROTOCOL_VERSION = "2024-11-05"

local M = {}

---@class ServerState
---@field server table|nil The TCP server instance.
---@field port number|nil The port server is running on.
---@field auth_token string|nil The authentication token for validating connections.
---@field handlers table Message handlers by method name.
---@field ping_timer table|nil Timer for sending pings.
M.state = {
  server = nil,
  port = nil,
  auth_token = nil,
  handlers = {},
  ping_timer = nil,
}

---@param config table
---@param auth_token string|nil
---@return boolean success
---@return number|string port_or_error
function M.start(config, auth_token)
  if M.state.server then
    return false, "Server already running"
  end

  M.state.auth_token = auth_token

  if auth_token then
    logger.debug("server", "Starting WebSocket server with authentication enabled")
  else
    logger.debug("server", "Starting WebSocket server WITHOUT authentication")
  end

  M.register_handlers()

  local callbacks = {
    on_message = function(client, message)
      M._handle_message(client, message)
    end,
    on_connect = function(client)
      if M.state.auth_token then
        logger.debug("server", "Authenticated WebSocket client connected:", client.id)
      else
        logger.debug("server", "WebSocket client connected:", client.id)
      end
    end,
    on_disconnect = function(client, code, reason)
      logger.debug(
        "server",
        "WebSocket client disconnected:",
        client.id,
        "(code:",
        code,
        ", reason:",
        (reason or "N/A") .. ")"
      )
    end,
    on_error = function(error_msg)
      logger.error("server", "WebSocket server error:", error_msg)
    end,
  }

  local server, error_msg = tcp_server.create_server(config, callbacks, M.state.auth_token)
  if not server then
    return false, error_msg or "Unknown server creation error"
  end

  M.state.server = server
  M.state.port = server.port
  M.state.ping_timer = tcp_server.start_ping_timer(server, 30000)

  return true, server.port
end

---@return boolean success
---@return string|nil error_message
function M.stop()
  if not M.state.server then
    return false, "Server not running"
  end

  if M.state.ping_timer then
    M.state.ping_timer:stop()
    M.state.ping_timer:close()
    M.state.ping_timer = nil
  end

  tcp_server.stop_server(M.state.server)

  M.state.server = nil
  M.state.port = nil
  M.state.auth_token = nil

  return true
end

---@param client table
---@param message string
function M._handle_message(client, message)
  local success, parsed = pcall(vim.json.decode, message)
  if not success then
    M.send_response(client, nil, nil, {
      code = -32700,
      message = "Parse error",
      data = "Invalid JSON",
    })
    return
  end

  if type(parsed) ~= "table" or parsed.jsonrpc ~= "2.0" then
    local request_id = type(parsed) == "table" and parsed.id or nil
    M.send_response(client, request_id, nil, {
      code = -32600,
      message = "Invalid Request",
      data = "Not a valid JSON-RPC 2.0 request",
    })
    return
  end

  if parsed.id then
    M._handle_request(client, parsed)
  else
    M._handle_notification(client, parsed)
  end
end

---@param client table
---@param request table
function M._handle_request(client, request)
  local method = request.method
  local params = request.params or {}
  local id = request.id

  local handler = M.state.handlers[method]
  if not handler then
    M.send_response(client, id, nil, {
      code = -32601,
      message = "Method not found",
      data = "Unknown method: " .. tostring(method),
    })
    return
  end

  local success, result, error_data = pcall(handler, client, params)
  if success then
    if error_data then
      M.send_response(client, id, nil, error_data)
    else
      M.send_response(client, id, result, nil)
    end
  else
    M.send_response(client, id, nil, {
      code = -32603,
      message = "Internal error",
      data = tostring(result),
    })
  end
end

---@param client table
---@param notification table
function M._handle_notification(client, notification)
  local handler = M.state.handlers[notification.method]
  if handler then
    pcall(handler, client, notification.params or {})
  end
end

function M.register_handlers()
  M.state.handlers = {
    ["initialize"] = function()
      return {
        protocolVersion = MCP_PROTOCOL_VERSION,
        capabilities = {
          tools = { listChanged = true },
        },
        serverInfo = {
          name = "claudecode-neovim",
          version = claudecode_main.version:string(),
        },
      }
    end,

    ["tools/list"] = function()
      return {
        tools = {},
      }
    end,

    ["tools/call"] = function(_client, params)
      return nil,
        {
          code = -32601,
          message = "No tools available",
          data = "Unknown tool: " .. tostring(params and params.name),
        }
    end,
  }
end

---@param client table
---@param id number|string|nil
---@param result any|nil
---@param error_data table|nil
---@return boolean success
function M.send_response(client, id, result, error_data)
  if not M.state.server then
    return false
  end

  local response = {
    jsonrpc = "2.0",
    id = id,
  }

  if error_data then
    response.error = error_data
  else
    response.result = result
  end

  local json_response = vim.json.encode(response)
  tcp_server.send_to_client(M.state.server, client.id, json_response)
  return true
end

---@return table status
function M.get_status()
  if not M.state.server then
    return {
      running = false,
      port = nil,
      client_count = 0,
    }
  end

  return {
    running = true,
    port = M.state.port,
    client_count = tcp_server.get_client_count(M.state.server),
  }
end

return M
