--- Tests for lua/claudecode/server/frame.lua

describe("server/frame", function()
  local frame

  before_each(function()
    package.loaded["claudecode.server.frame"] = nil
    package.loaded["claudecode.server.utils"] = nil
    frame = require("claudecode.server.frame")
  end)

  describe("frame protocol", function()
    it("roundtrips text, binary, close, ping, and pong frames", function()
      assert.equals("Hello", frame.parse_frame(frame.create_text_frame("Hello")).payload)
      assert.equals("\x00\x01\x02", frame.parse_frame(frame.create_frame(frame.OPCODE.BINARY, "\x00\x01\x02", true, false)).payload)
      assert.equals(frame.OPCODE.CLOSE, frame.parse_frame(frame.create_close_frame(1000, "done")).opcode)
      assert.equals("ping", frame.parse_frame(frame.create_ping_frame("ping")).payload)
      assert.equals("pong", frame.parse_frame(frame.create_pong_frame("pong")).payload)
    end)

    it("handles extended payload sizes and masked client frames", function()
      local medium = string.rep("x", 200)
      assert.equals(medium, frame.parse_frame(frame.create_text_frame(medium)).payload)

      local mask = "\x01\x02\x03\x04"
      local masked_payload = require("claudecode.server.utils").apply_mask("Hi", mask)
      local parsed = frame.parse_frame("\x81\x82" .. mask .. masked_payload)
      assert.equals("Hi", parsed.payload)
    end)

    it("rejects invalid protocol frames", function()
      assert.is_nil(frame.parse_frame("\x83\x00"))
      assert.is_nil(frame.parse_frame("\xC1\x00"))
      assert.is_nil(frame.parse_frame("\x08\x00"))
      assert.is_nil(frame.parse_frame("\x89\x7E\x00\x80"))
      assert.is_nil(frame.parse_frame("\x88\x01\x00"))
      assert.is_nil(frame.parse_frame("\x81\x03\x80\x81\x82"))
    end)
  end)
end)
