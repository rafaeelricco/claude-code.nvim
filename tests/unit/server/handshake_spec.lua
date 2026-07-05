--- Tests for lua/claudecode/server/handshake.lua

describe("server/handshake", function()
  local handshake

  local function value_or_false(value, fallback)
    if value == false then
      return nil
    end
    return value or fallback
  end

  local function make_request(overrides)
    overrides = overrides or {}

    local method = value_or_false(overrides.method, "GET")
    local path = value_or_false(overrides.path, "/")
    local version = value_or_false(overrides.version, "HTTP/1.1")
    local upgrade = value_or_false(overrides.upgrade, "websocket")
    local connection = value_or_false(overrides.connection, "Upgrade")
    local key = value_or_false(overrides.key, "dGhlIHNhbXBsZSBub25jZQ==")
    local ws_version = value_or_false(overrides.ws_version, "13")

    local lines = {
      method .. " " .. path .. " " .. version,
    }

    if upgrade then
      table.insert(lines, "Upgrade: " .. upgrade)
    end
    if connection then
      table.insert(lines, "Connection: " .. connection)
    end
    if key then
      table.insert(lines, "Sec-WebSocket-Key: " .. key)
    end
    if ws_version then
      table.insert(lines, "Sec-WebSocket-Version: " .. ws_version)
    end
    if overrides.auth_token then
      table.insert(lines, "x-claude-code-ide-authorization: " .. overrides.auth_token)
    end

    table.insert(lines, "")
    table.insert(lines, "")

    return table.concat(lines, "\r\n")
  end

  before_each(function()
    package.loaded["claudecode.server.utils"] = nil
    package.loaded["claudecode.server.handshake"] = nil
    handshake = require("claudecode.server.handshake")
  end)

  describe("handshake contract", function()
    it("accepts valid WebSocket handshakes and returns RFC accept key", function()
      local success, response, headers = handshake.process_handshake(make_request(), nil)

      assert.is_true(success)
      assert.is_truthy(response:match("HTTP/1%.1 101"))
      assert.is_truthy(response:match("s3pPLMBiTxaQ9kYGzzhZRbK%+xOo="))
      assert.equals("websocket", headers["upgrade"])
    end)

    it("rejects invalid endpoint or upgrade requests", function()
      assert.is_false(handshake.process_handshake(make_request({ method = "POST" }), nil))
      assert.is_false(handshake.process_handshake(make_request({ upgrade = false }), nil))
      assert.is_false(handshake.process_handshake(make_request({ key = "tooshort" }), nil))
    end)

    it("enforces auth token when configured", function()
      local token = "valid-auth-token-12345"
      assert.is_true(handshake.process_handshake(make_request({ auth_token = token }), token))
      assert.is_false(handshake.process_handshake(make_request(), token))
      assert.is_false(handshake.process_handshake(make_request({ auth_token = "wrong-token" }), token))
    end)

    it("extracts complete HTTP headers and keeps remaining frame data", function()
      local complete, request, remaining = handshake.extract_http_request("GET / HTTP/1.1\r\n\r\nExtra")

      assert.is_true(complete)
      assert.equals("GET / HTTP/1.1\r\n\r\n", request)
      assert.equals("Extra", remaining)
    end)
  end)
end)
