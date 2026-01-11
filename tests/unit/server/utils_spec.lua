--- Tests for lua/claudecode/server/utils.lua
--- Pure Lua utilities - no vim dependencies required

describe("server/utils", function()
  local utils

  before_each(function()
    package.loaded["claudecode.server.utils"] = nil
    utils = require("claudecode.server.utils")
  end)

  describe("base64_encode", function()
    it("encodes empty string", function()
      assert.equals("", utils.base64_encode(""))
    end)

    it("encodes 'Hello'", function()
      assert.equals("SGVsbG8=", utils.base64_encode("Hello"))
    end)

    it("encodes 'Hello, World!'", function()
      assert.equals("SGVsbG8sIFdvcmxkIQ==", utils.base64_encode("Hello, World!"))
    end)

    it("encodes single character", function()
      assert.equals("YQ==", utils.base64_encode("a"))
    end)

    it("encodes two characters", function()
      assert.equals("YWI=", utils.base64_encode("ab"))
    end)

    it("encodes three characters (no padding)", function()
      assert.equals("YWJj", utils.base64_encode("abc"))
    end)

    it("encodes binary data with null bytes", function()
      local binary = "\0\1\2\3"
      local encoded = utils.base64_encode(binary)
      assert.is_string(encoded)
      assert.is_true(#encoded > 0)
    end)

    it("encodes all printable ASCII characters", function()
      local ascii = ""
      for i = 32, 126 do
        ascii = ascii .. string.char(i)
      end
      local encoded = utils.base64_encode(ascii)
      assert.is_string(encoded)
      -- Verify it only contains valid base64 characters
      assert.is_nil(encoded:match("[^A-Za-z0-9+/=]"))
    end)

    it("handles 256-byte input", function()
      local data = string.rep("x", 256)
      local encoded = utils.base64_encode(data)
      assert.is_string(encoded)
    end)
  end)

  describe("base64_decode", function()
    it("decodes empty string", function()
      assert.equals("", utils.base64_decode(""))
    end)

    it("decodes 'SGVsbG8='", function()
      assert.equals("Hello", utils.base64_decode("SGVsbG8="))
    end)

    it("decodes 'SGVsbG8sIFdvcmxkIQ=='", function()
      assert.equals("Hello, World!", utils.base64_decode("SGVsbG8sIFdvcmxkIQ=="))
    end)

    it("decodes single character with padding", function()
      assert.equals("a", utils.base64_decode("YQ=="))
    end)

    it("decodes two characters with padding", function()
      assert.equals("ab", utils.base64_decode("YWI="))
    end)

    it("decodes three characters (no padding)", function()
      assert.equals("abc", utils.base64_decode("YWJj"))
    end)

    it("returns nil for invalid characters", function()
      assert.is_nil(utils.base64_decode("SGVs!G8="))
    end)

    it("returns nil for invalid character $", function()
      assert.is_nil(utils.base64_decode("$$$"))
    end)

    it("roundtrips with encode", function()
      local original = "Test string with special chars: !@#$%"
      local encoded = utils.base64_encode(original)
      local decoded = utils.base64_decode(encoded)
      assert.equals(original, decoded)
    end)

    it("roundtrips binary data", function()
      local binary = ""
      for i = 0, 255 do
        binary = binary .. string.char(i)
      end
      local encoded = utils.base64_encode(binary)
      local decoded = utils.base64_decode(encoded)
      assert.equals(binary, decoded)
    end)
  end)

  describe("sha1", function()
    -- Test vectors from RFC 3174
    it("hashes empty string correctly", function()
      local hash = utils.sha1("")
      local hex = ""
      for i = 1, #hash do
        hex = hex .. string.format("%02x", hash:byte(i))
      end
      assert.equals("da39a3ee5e6b4b0d3255bfef95601890afd80709", hex)
    end)

    it("hashes 'abc' correctly", function()
      local hash = utils.sha1("abc")
      local hex = ""
      for i = 1, #hash do
        hex = hex .. string.format("%02x", hash:byte(i))
      end
      assert.equals("a9993e364706816aba3e25717850c26c9cd0d89d", hex)
    end)

    it("hashes 'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq' correctly", function()
      local hash = utils.sha1("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
      local hex = ""
      for i = 1, #hash do
        hex = hex .. string.format("%02x", hash:byte(i))
      end
      assert.equals("84983e441c3bd26ebaae4aa1f95129e5e54670f1", hex)
    end)

    it("returns 20 bytes (160 bits)", function()
      local hash = utils.sha1("test")
      assert.equals(20, #hash)
    end)

    it("returns nil for non-string input", function()
      assert.is_nil(utils.sha1(123))
      assert.is_nil(utils.sha1(nil))
      assert.is_nil(utils.sha1({}))
    end)

    it("produces different hashes for different inputs", function()
      local hash1 = utils.sha1("test1")
      local hash2 = utils.sha1("test2")
      assert.is_not.equals(hash1, hash2)
    end)

    it("produces same hash for same input", function()
      local hash1 = utils.sha1("consistent")
      local hash2 = utils.sha1("consistent")
      assert.equals(hash1, hash2)
    end)

    it("handles input with null bytes", function()
      local hash = utils.sha1("test\0null\0bytes")
      assert.equals(20, #hash)
    end)
  end)

  describe("generate_accept_key", function()
    -- Known WebSocket accept key calculation
    it("generates correct accept key for known input", function()
      -- Example from RFC 6455
      local client_key = "dGhlIHNhbXBsZSBub25jZQ=="
      local accept_key = utils.generate_accept_key(client_key)
      assert.equals("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", accept_key)
    end)

    it("returns string", function()
      local key = utils.generate_accept_key("somekey123456789012345678")
      assert.is_string(key)
    end)

    it("produces consistent results", function()
      local key1 = utils.generate_accept_key("testkey")
      local key2 = utils.generate_accept_key("testkey")
      assert.equals(key1, key2)
    end)

    it("produces different results for different inputs", function()
      local key1 = utils.generate_accept_key("key1")
      local key2 = utils.generate_accept_key("key2")
      assert.is_not.equals(key1, key2)
    end)
  end)

  describe("generate_websocket_key", function()
    it("returns a string", function()
      local key = utils.generate_websocket_key()
      assert.is_string(key)
    end)

    it("returns 24 character base64 string (16 bytes encoded)", function()
      local key = utils.generate_websocket_key()
      assert.equals(24, #key)
    end)

    it("contains only valid base64 characters", function()
      local key = utils.generate_websocket_key()
      assert.is_nil(key:match("[^A-Za-z0-9+/=]"))
    end)

    it("generates different keys on multiple calls", function()
      local keys = {}
      for _ = 1, 10 do
        local key = utils.generate_websocket_key()
        assert.is_nil(keys[key], "Duplicate key generated")
        keys[key] = true
      end
    end)
  end)

  describe("parse_http_headers", function()
    it("parses simple headers", function()
      local request = "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n"
      local headers = utils.parse_http_headers(request)
      assert.equals("localhost", headers["host"])
      assert.equals("keep-alive", headers["connection"])
    end)

    it("handles case-insensitive header names", function()
      local request = "GET / HTTP/1.1\r\nContent-Type: text/plain\r\n\r\n"
      local headers = utils.parse_http_headers(request)
      assert.equals("text/plain", headers["content-type"])
    end)

    it("handles WebSocket upgrade headers", function()
      local request = "GET / HTTP/1.1\r\n"
        .. "Upgrade: websocket\r\n"
        .. "Connection: Upgrade\r\n"
        .. "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
        .. "Sec-WebSocket-Version: 13\r\n\r\n"
      local headers = utils.parse_http_headers(request)
      assert.equals("websocket", headers["upgrade"])
      assert.equals("Upgrade", headers["connection"])
      assert.equals("dGhlIHNhbXBsZSBub25jZQ==", headers["sec-websocket-key"])
      assert.equals("13", headers["sec-websocket-version"])
    end)

    it("handles headers with colons in values", function()
      local request = "GET / HTTP/1.1\r\nX-Custom: value:with:colons\r\n\r\n"
      local headers = utils.parse_http_headers(request)
      assert.equals("value:with:colons", headers["x-custom"])
    end)

    it("returns empty table for empty request", function()
      local headers = utils.parse_http_headers("")
      assert.is_table(headers)
    end)

    it("returns empty table for request with only request line", function()
      local headers = utils.parse_http_headers("GET / HTTP/1.1")
      assert.is_table(headers)
      assert.is_nil(next(headers))
    end)
  end)

  describe("is_valid_utf8", function()
    it("validates ASCII strings", function()
      assert.is_true(utils.is_valid_utf8("Hello, World!"))
    end)

    it("validates empty string", function()
      assert.is_true(utils.is_valid_utf8(""))
    end)

    it("validates 2-byte UTF-8 sequences", function()
      -- Latin characters with diacritics: "café"
      assert.is_true(utils.is_valid_utf8("caf\xC3\xA9"))
    end)

    it("validates 3-byte UTF-8 sequences", function()
      -- Euro sign: €
      assert.is_true(utils.is_valid_utf8("\xE2\x82\xAC"))
    end)

    it("validates 4-byte UTF-8 sequences", function()
      -- Emoji: 😀 (U+1F600)
      assert.is_true(utils.is_valid_utf8("\xF0\x9F\x98\x80"))
    end)

    it("rejects invalid continuation byte", function()
      -- Start of 2-byte sequence followed by non-continuation
      assert.is_false(utils.is_valid_utf8("\xC3\x28"))
    end)

    it("rejects orphaned continuation byte", function()
      -- Continuation byte without leading byte
      assert.is_false(utils.is_valid_utf8("\x80"))
    end)

    it("rejects incomplete 2-byte sequence", function()
      -- Start of 2-byte sequence at end of string
      assert.is_false(utils.is_valid_utf8("\xC3"))
    end)

    it("rejects incomplete 3-byte sequence", function()
      -- Start of 3-byte sequence with only one continuation
      assert.is_false(utils.is_valid_utf8("\xE2\x82"))
    end)

    it("rejects incomplete 4-byte sequence", function()
      -- Start of 4-byte sequence incomplete
      assert.is_false(utils.is_valid_utf8("\xF0\x9F\x98"))
    end)

    it("validates mixed ASCII and UTF-8", function()
      assert.is_true(utils.is_valid_utf8("Hello \xC3\xA9 World \xE2\x82\xAC"))
    end)
  end)

  describe("uint16_to_bytes", function()
    it("converts 0 to bytes", function()
      local bytes = utils.uint16_to_bytes(0)
      assert.equals(2, #bytes)
      assert.equals(0, bytes:byte(1))
      assert.equals(0, bytes:byte(2))
    end)

    it("converts 256 to bytes (big-endian)", function()
      local bytes = utils.uint16_to_bytes(256)
      assert.equals(2, #bytes)
      assert.equals(1, bytes:byte(1))
      assert.equals(0, bytes:byte(2))
    end)

    it("converts 65535 (max) to bytes", function()
      local bytes = utils.uint16_to_bytes(65535)
      assert.equals(2, #bytes)
      assert.equals(255, bytes:byte(1))
      assert.equals(255, bytes:byte(2))
    end)

    it("converts 0x1234 to bytes", function()
      local bytes = utils.uint16_to_bytes(0x1234)
      assert.equals(2, #bytes)
      assert.equals(0x12, bytes:byte(1))
      assert.equals(0x34, bytes:byte(2))
    end)
  end)

  describe("bytes_to_uint16", function()
    it("converts zero bytes to 0", function()
      assert.equals(0, utils.bytes_to_uint16("\0\0"))
    end)

    it("converts max bytes to 65535", function()
      assert.equals(65535, utils.bytes_to_uint16("\xff\xff"))
    end)

    it("handles big-endian format", function()
      assert.equals(256, utils.bytes_to_uint16("\x01\x00"))
    end)

    it("converts 0x1234", function()
      assert.equals(0x1234, utils.bytes_to_uint16("\x12\x34"))
    end)

    it("returns 0 for short input", function()
      assert.equals(0, utils.bytes_to_uint16("\x01"))
    end)

    it("returns 0 for empty input", function()
      assert.equals(0, utils.bytes_to_uint16(""))
    end)

    it("roundtrips with uint16_to_bytes", function()
      for _, num in ipairs({ 0, 1, 127, 128, 255, 256, 32767, 65535 }) do
        local bytes = utils.uint16_to_bytes(num)
        local result = utils.bytes_to_uint16(bytes)
        assert.equals(num, result)
      end
    end)
  end)

  describe("uint64_to_bytes", function()
    it("converts 0 to 8 bytes", function()
      local bytes = utils.uint64_to_bytes(0)
      assert.equals(8, #bytes)
      for i = 1, 8 do
        assert.equals(0, bytes:byte(i))
      end
    end)

    it("converts 1 to bytes", function()
      local bytes = utils.uint64_to_bytes(1)
      assert.equals(8, #bytes)
      assert.equals(1, bytes:byte(8))
    end)

    it("converts 256 to bytes", function()
      local bytes = utils.uint64_to_bytes(256)
      assert.equals(8, #bytes)
      assert.equals(1, bytes:byte(7))
      assert.equals(0, bytes:byte(8))
    end)
  end)

  describe("bytes_to_uint64", function()
    it("converts zero bytes to 0", function()
      assert.equals(0, utils.bytes_to_uint64("\0\0\0\0\0\0\0\0"))
    end)

    it("converts 1", function()
      assert.equals(1, utils.bytes_to_uint64("\0\0\0\0\0\0\0\1"))
    end)

    it("converts 256", function()
      assert.equals(256, utils.bytes_to_uint64("\0\0\0\0\0\0\1\0"))
    end)

    it("returns 0 for short input", function()
      assert.equals(0, utils.bytes_to_uint64("\x01"))
    end)

    it("roundtrips with uint64_to_bytes for reasonable values", function()
      -- Note: Lua numbers are doubles, so precision limited
      for _, num in ipairs({ 0, 1, 255, 256, 65535, 65536, 16777215 }) do
        local bytes = utils.uint64_to_bytes(num)
        local result = utils.bytes_to_uint64(bytes)
        assert.equals(num, result)
      end
    end)
  end)

  describe("apply_mask", function()
    it("masks empty data", function()
      local result = utils.apply_mask("", "\x01\x02\x03\x04")
      assert.equals("", result)
    end)

    it("masks single byte", function()
      local data = "\x00"
      local mask = "\x01\x02\x03\x04"
      local masked = utils.apply_mask(data, mask)
      assert.equals("\x01", masked) -- 0x00 XOR 0x01 = 0x01
    end)

    it("masks multiple bytes with cycling mask", function()
      local data = "\x00\x00\x00\x00"
      local mask = "\x01\x02\x03\x04"
      local masked = utils.apply_mask(data, mask)
      assert.equals("\x01\x02\x03\x04", masked)
    end)

    it("unmasking is symmetric (XOR twice = original)", function()
      local original = "Hello, World!"
      local mask = "\xAB\xCD\xEF\x01"
      local masked = utils.apply_mask(original, mask)
      local unmasked = utils.apply_mask(masked, mask)
      assert.equals(original, unmasked)
    end)

    it("handles mask cycling for longer data", function()
      local data = string.rep("\x00", 8)
      local mask = "\x01\x02\x03\x04"
      local masked = utils.apply_mask(data, mask)
      assert.equals("\x01\x02\x03\x04\x01\x02\x03\x04", masked)
    end)

    it("handles binary data", function()
      local data = "\xFF\xFE\xFD\xFC"
      local mask = "\x01\x02\x03\x04"
      local masked = utils.apply_mask(data, mask)
      -- 0xFF XOR 0x01 = 0xFE, 0xFE XOR 0x02 = 0xFC, 0xFD XOR 0x03 = 0xFE, 0xFC XOR 0x04 = 0xF8
      assert.equals("\xFE\xFC\xFE\xF8", masked)
    end)
  end)

  describe("shuffle_array", function()
    it("handles empty array", function()
      local tbl = {}
      utils.shuffle_array(tbl)
      assert.equals(0, #tbl)
    end)

    it("handles single element", function()
      local tbl = { 1 }
      utils.shuffle_array(tbl)
      assert.equals(1, #tbl)
      assert.equals(1, tbl[1])
    end)

    it("preserves all elements", function()
      local tbl = { 1, 2, 3, 4, 5 }
      utils.shuffle_array(tbl)
      assert.equals(5, #tbl)

      local found = {}
      for _, v in ipairs(tbl) do
        found[v] = true
      end

      for i = 1, 5 do
        assert.is_true(found[i], "Missing element " .. i)
      end
    end)

    it("modifies array in place", function()
      local tbl = { 1, 2, 3 }
      local original_ref = tbl
      utils.shuffle_array(tbl)
      assert.equals(original_ref, tbl)
    end)
  end)
end)
