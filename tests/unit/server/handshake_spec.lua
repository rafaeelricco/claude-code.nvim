--- Tests for lua/claudecode/server/handshake.lua
--- WebSocket handshake handling (RFC 6455)

describe("server/handshake", function()
  local handshake

  -- Helper to create a valid WebSocket upgrade request
  local function make_request(overrides)
    overrides = overrides or {}
    local headers = {
      method = overrides.method or "GET",
      path = overrides.path or "/",
      version = overrides.version or "HTTP/1.1",
      upgrade = overrides.upgrade or "websocket",
      connection = overrides.connection or "Upgrade",
      key = overrides.key or "dGhlIHNhbXBsZSBub25jZQ==",
      ws_version = overrides.ws_version or "13",
      auth_token = overrides.auth_token,
    }

    local lines = {
      headers.method .. " " .. headers.path .. " " .. headers.version,
    }

    if headers.upgrade then
      table.insert(lines, "Upgrade: " .. headers.upgrade)
    end
    if headers.connection then
      table.insert(lines, "Connection: " .. headers.connection)
    end
    if headers.key then
      table.insert(lines, "Sec-WebSocket-Key: " .. headers.key)
    end
    if headers.ws_version then
      table.insert(lines, "Sec-WebSocket-Version: " .. headers.ws_version)
    end
    if headers.auth_token then
      table.insert(lines, "x-claude-code-ide-authorization: " .. headers.auth_token)
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

  describe("parse_request_line", function()
    it("parses valid GET request", function()
      local request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
      local method, path, version = handshake.parse_request_line(request)
      assert.equals("GET", method)
      assert.equals("/", path)
      assert.equals("HTTP/1.1", version)
    end)

    it("parses POST request", function()
      local request = "POST /api HTTP/1.1\r\n\r\n"
      local method, path, version = handshake.parse_request_line(request)
      assert.equals("POST", method)
      assert.equals("/api", path)
    end)

    it("returns nil for empty request", function()
      local method, path, version = handshake.parse_request_line("")
      assert.is_nil(method)
    end)

    it("returns nil for malformed request line", function()
      local request = "INVALID"
      local method, path, version = handshake.parse_request_line(request)
      assert.is_nil(method)
    end)

    it("handles request with path containing query string", function()
      local request = "GET /path?query=1 HTTP/1.1\r\n\r\n"
      local method, path, version = handshake.parse_request_line(request)
      assert.equals("GET", method)
      assert.equals("/path?query=1", path)
    end)
  end)

  describe("is_websocket_endpoint", function()
    it("returns true for valid GET request", function()
      local request = make_request()
      assert.is_true(handshake.is_websocket_endpoint(request))
    end)

    it("returns false for POST request", function()
      local request = make_request({ method = "POST" })
      assert.is_false(handshake.is_websocket_endpoint(request))
    end)

    it("returns false for HTTP/1.0", function()
      local request = make_request({ version = "HTTP/1.0" })
      assert.is_false(handshake.is_websocket_endpoint(request))
    end)

    it("returns true for HTTP/1.1", function()
      local request = make_request({ version = "HTTP/1.1" })
      assert.is_true(handshake.is_websocket_endpoint(request))
    end)

    it("returns false for empty request", function()
      assert.is_false(handshake.is_websocket_endpoint(""))
    end)
  end)

  describe("validate_upgrade_request", function()
    it("validates correct upgrade request", function()
      local request = make_request()
      local valid, headers = handshake.validate_upgrade_request(request, nil)
      assert.is_true(valid)
      assert.is_table(headers)
    end)

    it("fails without Upgrade header", function()
      local request = make_request({ upgrade = nil })
      local valid, err = handshake.validate_upgrade_request(request, nil)
      assert.is_false(valid)
      assert.is_truthy(err:match("Upgrade"))
    end)

    it("fails with wrong Upgrade value", function()
      local request = make_request({ upgrade = "http/2" })
      local valid, err = handshake.validate_upgrade_request(request, nil)
      assert.is_false(valid)
    end)

    it("fails without Connection header", function()
      local request = make_request({ connection = nil })
      local valid, err = handshake.validate_upgrade_request(request, nil)
      assert.is_false(valid)
      assert.is_truthy(err:match("Connection"))
    end)

    it("fails without Sec-WebSocket-Key", function()
      local request = make_request({ key = nil })
      local valid, err = handshake.validate_upgrade_request(request, nil)
      assert.is_false(valid)
      assert.is_truthy(err:match("Key"))
    end)

    it("fails with wrong key length", function()
      local request = make_request({ key = "tooshort" })
      local valid, err = handshake.validate_upgrade_request(request, nil)
      assert.is_false(valid)
      assert.is_truthy(err:match("format"))
    end)

    it("fails without Sec-WebSocket-Version", function()
      local request = make_request({ ws_version = nil })
      local valid, err = handshake.validate_upgrade_request(request, nil)
      assert.is_false(valid)
      assert.is_truthy(err:match("Version"))
    end)

    it("fails with wrong WebSocket version", function()
      local request = make_request({ ws_version = "8" })
      local valid, err = handshake.validate_upgrade_request(request, nil)
      assert.is_false(valid)
    end)

    -- Authentication tests
    it("validates with correct auth token", function()
      local token = "valid-auth-token-12345"
      local request = make_request({ auth_token = token })
      local valid, headers = handshake.validate_upgrade_request(request, token)
      assert.is_true(valid)
      assert.is_table(headers)
    end)

    it("fails with missing auth token when required", function()
      local request = make_request({ auth_token = nil })
      local valid, err = handshake.validate_upgrade_request(request, "expected-token")
      assert.is_false(valid)
      assert.is_truthy(err:match("authentication"))
    end)

    it("fails with wrong auth token", function()
      local request = make_request({ auth_token = "wrong-token-123" })
      local valid, err = handshake.validate_upgrade_request(request, "correct-token-456")
      assert.is_false(valid)
      assert.is_truthy(err:match("Invalid"))
    end)

    it("fails with empty auth token", function()
      local request = make_request({ auth_token = "" })
      local valid, err = handshake.validate_upgrade_request(request, "expected-token")
      assert.is_false(valid)
      assert.is_truthy(err:match("too short"))
    end)

    it("fails with too short auth token", function()
      local request = make_request({ auth_token = "short" })
      local valid, err = handshake.validate_upgrade_request(request, "expected-token")
      assert.is_false(valid)
      assert.is_truthy(err:match("too short"))
    end)

    it("fails with too long auth token", function()
      local long_token = string.rep("x", 501)
      local request = make_request({ auth_token = long_token })
      local valid, err = handshake.validate_upgrade_request(request, "expected-token")
      assert.is_false(valid)
      assert.is_truthy(err:match("too long"))
    end)

    it("handles case-insensitive Upgrade header", function()
      local request = make_request({ upgrade = "WebSocket" })
      local valid, headers = handshake.validate_upgrade_request(request, nil)
      assert.is_true(valid)
    end)
  end)

  describe("create_handshake_response", function()
    it("creates valid response", function()
      local key = "dGhlIHNhbXBsZSBub25jZQ=="
      local response = handshake.create_handshake_response(key, nil)

      assert.is_string(response)
      assert.is_truthy(response:match("HTTP/1%.1 101"))
      assert.is_truthy(response:match("Upgrade: websocket"))
      assert.is_truthy(response:match("Connection: Upgrade"))
      assert.is_truthy(response:match("Sec%-WebSocket%-Accept:"))
    end)

    it("includes correct accept key", function()
      -- Known test case from RFC 6455
      local key = "dGhlIHNhbXBsZSBub25jZQ=="
      local response = handshake.create_handshake_response(key, nil)
      assert.is_truthy(response:match("s3pPLMBiTxaQ9kYGzzhZRbK%+xOo="))
    end)

    it("includes subprotocol when specified", function()
      local key = "dGhlIHNhbXBsZSBub25jZQ=="
      local response = handshake.create_handshake_response(key, "chat")

      assert.is_truthy(response:match("Sec%-WebSocket%-Protocol: chat"))
    end)

    it("does not include subprotocol when nil", function()
      local key = "dGhlIHNhbXBsZSBub25jZQ=="
      local response = handshake.create_handshake_response(key, nil)

      assert.is_falsy(response:match("Sec%-WebSocket%-Protocol"))
    end)

    it("ends with double CRLF", function()
      local key = "dGhlIHNhbXBsZSBub25jZQ=="
      local response = handshake.create_handshake_response(key, nil)
      assert.is_truthy(response:match("\r\n\r\n$"))
    end)
  end)

  describe("create_error_response", function()
    it("creates 400 Bad Request", function()
      local response = handshake.create_error_response(400, "Bad request")
      assert.is_truthy(response:match("HTTP/1%.1 400 Bad Request"))
      assert.is_truthy(response:match("Bad request"))
    end)

    it("creates 404 Not Found", function()
      local response = handshake.create_error_response(404, "Not found")
      assert.is_truthy(response:match("HTTP/1%.1 404 Not Found"))
    end)

    it("creates 426 Upgrade Required", function()
      local response = handshake.create_error_response(426, "Upgrade needed")
      assert.is_truthy(response:match("HTTP/1%.1 426 Upgrade Required"))
    end)

    it("creates 500 Internal Server Error", function()
      local response = handshake.create_error_response(500, "Server error")
      assert.is_truthy(response:match("HTTP/1%.1 500 Internal Server Error"))
    end)

    it("includes Content-Type header", function()
      local response = handshake.create_error_response(400, "Error")
      assert.is_truthy(response:match("Content%-Type: text/plain"))
    end)

    it("includes correct Content-Length", function()
      local message = "Test error message"
      local response = handshake.create_error_response(400, message)
      assert.is_truthy(response:match("Content%-Length: " .. #message))
    end)

    it("includes Connection: close", function()
      local response = handshake.create_error_response(400, "Error")
      assert.is_truthy(response:match("Connection: close"))
    end)

    it("handles unknown status code", function()
      local response = handshake.create_error_response(999, "Unknown")
      assert.is_truthy(response:match("HTTP/1%.1 999 Error"))
    end)
  end)

  describe("extract_http_request", function()
    it("extracts complete request", function()
      local buffer = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
      local complete, request, remaining = handshake.extract_http_request(buffer)

      assert.is_true(complete)
      assert.equals(buffer, request)
      assert.equals("", remaining)
    end)

    it("returns incomplete for partial request", function()
      local buffer = "GET / HTTP/1.1\r\nHost: localhost"
      local complete, request, remaining = handshake.extract_http_request(buffer)

      assert.is_false(complete)
      assert.is_nil(request)
      assert.equals(buffer, remaining)
    end)

    it("returns remaining data after headers", function()
      local buffer = "GET / HTTP/1.1\r\n\r\nExtra data"
      local complete, request, remaining = handshake.extract_http_request(buffer)

      assert.is_true(complete)
      assert.is_not_nil(request)
      assert.equals("Extra data", remaining)
    end)

    it("handles empty buffer", function()
      local complete, request, remaining = handshake.extract_http_request("")
      assert.is_false(complete)
      assert.is_nil(request)
      assert.equals("", remaining)
    end)

    it("handles request with only single CRLF", function()
      local buffer = "GET / HTTP/1.1\r\n"
      local complete, request, remaining = handshake.extract_http_request(buffer)
      assert.is_false(complete)
    end)
  end)

  describe("process_handshake", function()
    it("processes valid handshake", function()
      local request = make_request()
      local success, response, headers = handshake.process_handshake(request, nil)

      assert.is_true(success)
      assert.is_truthy(response:match("HTTP/1%.1 101"))
      assert.is_table(headers)
    end)

    it("returns error for non-GET request", function()
      local request = make_request({ method = "POST" })
      local success, response, headers = handshake.process_handshake(request, nil)

      assert.is_false(success)
      assert.is_truthy(response:match("404"))
      assert.is_nil(headers)
    end)

    it("returns error for invalid upgrade", function()
      local request = make_request({ upgrade = nil })
      local success, response, headers = handshake.process_handshake(request, nil)

      assert.is_false(success)
      assert.is_truthy(response:match("400"))
      assert.is_nil(headers)
    end)

    it("processes handshake with valid auth token", function()
      local token = "valid-auth-token-12345"
      local request = make_request({ auth_token = token })
      local success, response, headers = handshake.process_handshake(request, token)

      assert.is_true(success)
      assert.is_truthy(response:match("HTTP/1%.1 101"))
    end)

    it("fails handshake with invalid auth token", function()
      local request = make_request({ auth_token = "wrong-token" })
      local success, response, headers = handshake.process_handshake(request, "correct-token")

      assert.is_false(success)
      assert.is_truthy(response:match("400"))
    end)

    it("returns headers on success", function()
      local request = make_request()
      local success, response, headers = handshake.process_handshake(request, nil)

      assert.is_true(success)
      assert.is_table(headers)
      assert.equals("websocket", headers["upgrade"])
    end)
  end)
end)
