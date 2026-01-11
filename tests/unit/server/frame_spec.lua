--- Tests for lua/claudecode/server/frame.lua
--- WebSocket frame encoding and decoding (RFC 6455)

describe("server/frame", function()
  local frame

  before_each(function()
    package.loaded["claudecode.server.utils"] = nil
    package.loaded["claudecode.server.frame"] = nil
    frame = require("claudecode.server.frame")
  end)

  describe("OPCODE constants", function()
    it("defines CONTINUATION as 0x0", function()
      assert.equals(0x0, frame.OPCODE.CONTINUATION)
    end)

    it("defines TEXT as 0x1", function()
      assert.equals(0x1, frame.OPCODE.TEXT)
    end)

    it("defines BINARY as 0x2", function()
      assert.equals(0x2, frame.OPCODE.BINARY)
    end)

    it("defines CLOSE as 0x8", function()
      assert.equals(0x8, frame.OPCODE.CLOSE)
    end)

    it("defines PING as 0x9", function()
      assert.equals(0x9, frame.OPCODE.PING)
    end)

    it("defines PONG as 0xA", function()
      assert.equals(0xA, frame.OPCODE.PONG)
    end)
  end)

  describe("is_control_frame", function()
    it("returns false for CONTINUATION", function()
      assert.is_false(frame.is_control_frame(frame.OPCODE.CONTINUATION))
    end)

    it("returns false for TEXT", function()
      assert.is_false(frame.is_control_frame(frame.OPCODE.TEXT))
    end)

    it("returns false for BINARY", function()
      assert.is_false(frame.is_control_frame(frame.OPCODE.BINARY))
    end)

    it("returns true for CLOSE", function()
      assert.is_true(frame.is_control_frame(frame.OPCODE.CLOSE))
    end)

    it("returns true for PING", function()
      assert.is_true(frame.is_control_frame(frame.OPCODE.PING))
    end)

    it("returns true for PONG", function()
      assert.is_true(frame.is_control_frame(frame.OPCODE.PONG))
    end)

    it("returns true for opcodes >= 0x8", function()
      for i = 0x8, 0xF do
        assert.is_true(frame.is_control_frame(i))
      end
    end)
  end)

  describe("create_frame", function()
    it("creates text frame with correct opcode", function()
      local data = frame.create_frame(frame.OPCODE.TEXT, "Hello", true, false)
      assert.equals(frame.OPCODE.TEXT + 0x80, data:byte(1)) -- FIN + opcode
    end)

    it("creates frame with FIN bit set by default", function()
      local data = frame.create_frame(frame.OPCODE.TEXT, "test", nil, false)
      local byte1 = data:byte(1)
      assert.is_true(byte1 >= 128) -- FIN bit is set
    end)

    it("creates frame without FIN bit when specified", function()
      local data = frame.create_frame(frame.OPCODE.TEXT, "test", false, false)
      local byte1 = data:byte(1)
      assert.equals(frame.OPCODE.TEXT, byte1) -- Just opcode, no FIN
    end)

    it("creates unmasked frame by default", function()
      local data = frame.create_frame(frame.OPCODE.TEXT, "test", true, false)
      local byte2 = data:byte(2)
      assert.is_true(byte2 < 128) -- Mask bit not set
    end)

    it("handles small payload length (< 126)", function()
      local payload = "Hello"
      local data = frame.create_frame(frame.OPCODE.TEXT, payload, true, false)
      assert.equals(5, data:byte(2)) -- Length directly in byte 2
      assert.equals(2 + 5, #data) -- Header + payload
    end)

    it("handles medium payload length (126-65535)", function()
      local payload = string.rep("x", 200)
      local data = frame.create_frame(frame.OPCODE.TEXT, payload, true, false)
      assert.equals(126, data:byte(2)) -- Extended length marker
      -- 2 header bytes + 2 extended length bytes + payload
      assert.equals(2 + 2 + 200, #data)
    end)

    it("handles large payload length (> 65535)", function()
      local payload = string.rep("x", 70000)
      local data = frame.create_frame(frame.OPCODE.TEXT, payload, true, false)
      assert.equals(127, data:byte(2)) -- 64-bit extended length marker
      -- 2 header bytes + 8 extended length bytes + payload
      assert.equals(2 + 8 + 70000, #data)
    end)

    it("creates masked frame when specified", function()
      local data = frame.create_frame(frame.OPCODE.TEXT, "test", true, true)
      local byte2 = data:byte(2)
      assert.is_true(byte2 >= 128) -- Mask bit is set
    end)
  end)

  describe("create_text_frame", function()
    it("creates text frame", function()
      local data = frame.create_text_frame("Hello")
      local byte1 = data:byte(1)
      assert.equals(frame.OPCODE.TEXT + 0x80, byte1)
    end)

    it("includes payload correctly", function()
      local data = frame.create_text_frame("Hi")
      assert.equals(2, data:byte(2)) -- Payload length
      assert.equals("Hi", data:sub(3))
    end)

    it("handles empty string", function()
      local data = frame.create_text_frame("")
      assert.equals(0, data:byte(2)) -- Zero payload length
    end)

    it("is not masked", function()
      local data = frame.create_text_frame("test")
      assert.is_true(data:byte(2) < 128)
    end)
  end)

  describe("create_binary_frame", function()
    it("creates binary frame", function()
      local data = frame.create_binary_frame("\x00\x01\x02")
      local byte1 = data:byte(1)
      assert.equals(frame.OPCODE.BINARY + 0x80, byte1)
    end)

    it("handles binary data with null bytes", function()
      local binary = "\x00\xFF\x00\xFF"
      local data = frame.create_binary_frame(binary)
      assert.equals(4, data:byte(2)) -- Payload length
    end)
  end)

  describe("create_close_frame", function()
    it("creates close frame with default code 1000", function()
      local data = frame.create_close_frame()
      local byte1 = data:byte(1)
      assert.equals(frame.OPCODE.CLOSE + 0x80, byte1)
      -- Payload contains 2-byte status code
      assert.equals(2, data:byte(2)) -- Payload length
    end)

    it("encodes close code correctly", function()
      local data = frame.create_close_frame(1001)
      -- Big-endian: 1001 = 0x03E9
      assert.equals(0x03, data:byte(3))
      assert.equals(0xE9, data:byte(4))
    end)

    it("includes reason text", function()
      local data = frame.create_close_frame(1000, "goodbye")
      assert.equals(2 + 7, data:byte(2)) -- Status code + reason length
    end)

    it("has FIN bit set (control frame)", function()
      local data = frame.create_close_frame(1000)
      assert.is_true(data:byte(1) >= 128)
    end)
  end)

  describe("create_ping_frame", function()
    it("creates ping frame", function()
      local data = frame.create_ping_frame()
      local byte1 = data:byte(1)
      assert.equals(frame.OPCODE.PING + 0x80, byte1)
    end)

    it("handles empty ping", function()
      local data = frame.create_ping_frame()
      assert.equals(0, data:byte(2))
    end)

    it("includes ping data", function()
      local data = frame.create_ping_frame("test")
      assert.equals(4, data:byte(2))
    end)
  end)

  describe("create_pong_frame", function()
    it("creates pong frame", function()
      local data = frame.create_pong_frame()
      local byte1 = data:byte(1)
      assert.equals(frame.OPCODE.PONG + 0x80, byte1)
    end)

    it("includes pong data", function()
      local data = frame.create_pong_frame("test")
      assert.equals(4, data:byte(2))
      assert.equals("test", data:sub(3))
    end)
  end)

  describe("parse_frame", function()
    it("parses simple text frame", function()
      local data = frame.create_text_frame("Hello")
      local parsed, consumed = frame.parse_frame(data)

      assert.is_not_nil(parsed)
      assert.is_true(parsed.fin)
      assert.equals(frame.OPCODE.TEXT, parsed.opcode)
      assert.equals("Hello", parsed.payload)
      assert.equals(#data, consumed)
    end)

    it("parses binary frame", function()
      local data = frame.create_binary_frame("\x00\x01\x02")
      local parsed, consumed = frame.parse_frame(data)

      assert.is_not_nil(parsed)
      assert.equals(frame.OPCODE.BINARY, parsed.opcode)
      assert.equals("\x00\x01\x02", parsed.payload)
    end)

    it("parses close frame", function()
      local data = frame.create_close_frame(1000, "goodbye")
      local parsed, consumed = frame.parse_frame(data)

      assert.is_not_nil(parsed)
      assert.equals(frame.OPCODE.CLOSE, parsed.opcode)
      -- Payload starts with 2-byte code
      local code = parsed.payload:byte(1) * 256 + parsed.payload:byte(2)
      assert.equals(1000, code)
    end)

    it("parses ping frame", function()
      local data = frame.create_ping_frame("ping")
      local parsed, consumed = frame.parse_frame(data)

      assert.is_not_nil(parsed)
      assert.equals(frame.OPCODE.PING, parsed.opcode)
      assert.equals("ping", parsed.payload)
    end)

    it("parses pong frame", function()
      local data = frame.create_pong_frame("pong")
      local parsed, consumed = frame.parse_frame(data)

      assert.is_not_nil(parsed)
      assert.equals(frame.OPCODE.PONG, parsed.opcode)
      assert.equals("pong", parsed.payload)
    end)

    it("returns nil for incomplete frame", function()
      local data = "\x81" -- Only first byte
      local parsed, consumed = frame.parse_frame(data)
      assert.is_nil(parsed)
      assert.equals(0, consumed)
    end)

    it("returns nil for non-string input", function()
      local parsed, consumed = frame.parse_frame(123)
      assert.is_nil(parsed)
      assert.equals(0, consumed)
    end)

    it("returns nil for nil input", function()
      local parsed, consumed = frame.parse_frame(nil)
      assert.is_nil(parsed)
      assert.equals(0, consumed)
    end)

    it("returns nil for invalid opcode", function()
      -- Create frame with invalid opcode 0x3
      local data = "\x83\x00" -- FIN=1, opcode=3, length=0
      local parsed, consumed = frame.parse_frame(data)
      assert.is_nil(parsed)
    end)

    it("returns nil for reserved bits set", function()
      -- Create frame with RSV1 bit set
      local data = "\xC1\x00" -- FIN=1, RSV1=1, opcode=1, length=0
      local parsed, consumed = frame.parse_frame(data)
      assert.is_nil(parsed)
    end)

    it("parses medium length frame (126-65535 bytes)", function()
      local payload = string.rep("x", 200)
      local data = frame.create_text_frame(payload)
      local parsed, consumed = frame.parse_frame(data)

      assert.is_not_nil(parsed)
      assert.equals(200, parsed.payload_length)
      assert.equals(payload, parsed.payload)
    end)

    it("parses frame without FIN bit", function()
      local data = frame.create_frame(frame.OPCODE.TEXT, "test", false, false)
      local parsed, consumed = frame.parse_frame(data)

      assert.is_not_nil(parsed)
      assert.is_false(parsed.fin)
    end)

    it("handles masked frame from client", function()
      -- Manually construct a masked frame
      local payload = "Hi"
      local mask = "\x01\x02\x03\x04"
      local masked_payload = ""
      for i = 1, #payload do
        local mask_byte = mask:byte(((i - 1) % 4) + 1)
        masked_payload = masked_payload .. string.char(bit32 and bit32.bxor(payload:byte(i), mask_byte) or ((payload:byte(i) + mask_byte) % 256))
      end

      -- Create masked frame manually: FIN=1, opcode=TEXT, MASK=1, length=2
      local utils = require("claudecode.server.utils")
      masked_payload = utils.apply_mask(payload, mask)

      local data = "\x81\x82" .. mask .. masked_payload -- 0x82 = MASK bit + length 2

      local parsed, consumed = frame.parse_frame(data)
      assert.is_not_nil(parsed)
      assert.is_true(parsed.masked)
      assert.equals("Hi", parsed.payload) -- Should be unmasked
    end)

    it("rejects control frame without FIN", function()
      -- Create close frame without FIN bit (invalid)
      local data = "\x08\x00" -- opcode=CLOSE, FIN=0, length=0
      local parsed, consumed = frame.parse_frame(data)
      assert.is_nil(parsed)
    end)

    it("rejects control frame with payload > 125", function()
      -- This would be invalid per RFC 6455
      -- Create frame header that claims control frame with large payload
      local data = "\x89\x7E\x00\x80" -- PING, length=126 (extended), claims 128 bytes
      local parsed, consumed = frame.parse_frame(data)
      assert.is_nil(parsed)
    end)

    it("rejects close frame with 1-byte payload", function()
      -- Close frame with 1 byte is invalid (needs 0 or 2+)
      local data = "\x88\x01\x00" -- CLOSE, length=1, one byte
      local parsed, consumed = frame.parse_frame(data)
      assert.is_nil(parsed)
    end)

    it("rejects text frame with invalid UTF-8", function()
      -- Create frame with invalid UTF-8 in payload
      local invalid_utf8 = "\x80\x81\x82" -- Orphan continuation bytes
      local data = "\x81\x03" .. invalid_utf8 -- TEXT frame
      local parsed, consumed = frame.parse_frame(data)
      assert.is_nil(parsed)
    end)
  end)

  describe("validate_frame", function()
    it("validates correct text frame", function()
      local f = {
        fin = true,
        opcode = frame.OPCODE.TEXT,
        payload = "Hello",
        payload_length = 5,
      }
      local valid, err = frame.validate_frame(f)
      assert.is_true(valid)
      assert.is_nil(err)
    end)

    it("validates correct binary frame", function()
      local f = {
        fin = true,
        opcode = frame.OPCODE.BINARY,
        payload = "\x00\x01",
        payload_length = 2,
      }
      local valid, err = frame.validate_frame(f)
      assert.is_true(valid)
    end)

    it("rejects fragmented control frame", function()
      local f = {
        fin = false, -- Control frames must have FIN
        opcode = frame.OPCODE.PING,
        payload = "",
        payload_length = 0,
      }
      local valid, err = frame.validate_frame(f)
      assert.is_false(valid)
      assert.is_not_nil(err)
      assert.is_truthy(err:match("fragmented"))
    end)

    it("rejects control frame with large payload", function()
      local f = {
        fin = true,
        opcode = frame.OPCODE.PONG,
        payload = string.rep("x", 126),
        payload_length = 126,
      }
      local valid, err = frame.validate_frame(f)
      assert.is_false(valid)
      assert.is_truthy(err:match("too large"))
    end)

    it("rejects invalid opcode", function()
      local f = {
        fin = true,
        opcode = 0x3, -- Invalid
        payload = "",
        payload_length = 0,
      }
      local valid, err = frame.validate_frame(f)
      assert.is_false(valid)
      assert.is_truthy(err:match("Invalid opcode"))
    end)

    it("rejects text frame with invalid UTF-8", function()
      local f = {
        fin = true,
        opcode = frame.OPCODE.TEXT,
        payload = "\x80\x81", -- Invalid UTF-8
        payload_length = 2,
      }
      local valid, err = frame.validate_frame(f)
      assert.is_false(valid)
      assert.is_truthy(err:match("UTF%-8"))
    end)

    it("accepts valid UTF-8 in text frame", function()
      local f = {
        fin = true,
        opcode = frame.OPCODE.TEXT,
        payload = "Hello, World!",
        payload_length = 13,
      }
      local valid, err = frame.validate_frame(f)
      assert.is_true(valid)
    end)
  end)

  describe("roundtrip tests", function()
    it("roundtrips text frame", function()
      local original = "Hello, World!"
      local data = frame.create_text_frame(original)
      local parsed = frame.parse_frame(data)
      assert.equals(original, parsed.payload)
    end)

    it("roundtrips binary frame with all byte values", function()
      local binary = ""
      for i = 0, 255 do
        binary = binary .. string.char(i)
      end
      local data = frame.create_binary_frame(binary)
      local parsed = frame.parse_frame(data)
      assert.equals(binary, parsed.payload)
    end)

    it("roundtrips close frame", function()
      local data = frame.create_close_frame(1001, "going away")
      local parsed = frame.parse_frame(data)
      local code = parsed.payload:byte(1) * 256 + parsed.payload:byte(2)
      local reason = parsed.payload:sub(3)
      assert.equals(1001, code)
      assert.equals("going away", reason)
    end)

    it("roundtrips ping frame", function()
      local ping_data = "ping123"
      local data = frame.create_ping_frame(ping_data)
      local parsed = frame.parse_frame(data)
      assert.equals(ping_data, parsed.payload)
    end)

    it("roundtrips pong frame", function()
      local pong_data = "pong456"
      local data = frame.create_pong_frame(pong_data)
      local parsed = frame.parse_frame(data)
      assert.equals(pong_data, parsed.payload)
    end)
  end)
end)
