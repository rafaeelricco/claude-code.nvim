--- Tests for lua/claudecode/config.lua

if not vim then
  require("tests.helpers.mock_vim").setup()
end

describe("config", function()
  local config

  before_each(function()
    package.loaded["claudecode.config"] = nil
    config = require("claudecode.config")
  end)

  describe("headless config contract", function()
    it("keeps only the supported defaults", function()
      assert.same({ min = 10000, max = 65535 }, config.defaults.port_range)
      assert.equals(true, config.defaults.auto_start)
      assert.equals("info", config.defaults.log_level)
      assert.is_nil(config.defaults.terminal_cmd)
      assert.is_nil(config.defaults.track_selection)
      assert.is_nil(config.defaults.diff_opts)
    end)
  end)

  describe("validate", function()
    it("accepts the valid headless config shape", function()
      assert.is_true(config.validate({
        port_range = { min = 10000, max = 65535 },
        auto_start = false,
        log_level = "debug",
      }))
    end)

    it("rejects invalid port ranges, auto_start, and log_level", function()
      assert.has_error(function()
        config.validate({ port_range = { min = 0, max = 65535 }, auto_start = true, log_level = "info" })
      end, "Invalid port range")

      assert.has_error(function()
        config.validate({ port_range = { min = 10000, max = 65535 }, auto_start = "true", log_level = "info" })
      end, "auto_start must be a boolean")

      assert.has_error(function()
        config.validate({ port_range = { min = 10000, max = 65535 }, auto_start = true, log_level = "INFO" })
      end)
    end)
  end)

  describe("apply", function()
    it("merges known keys and ignores unknown keys", function()
      local result = config.apply({
        port_range = { min = 20000 },
        auto_start = false,
        log_level = "error",
        terminal_cmd = "claude",
      })

      assert.same({ min = 20000, max = 65535 }, result.port_range)
      assert.equals(false, result.auto_start)
      assert.equals("error", result.log_level)
      assert.is_nil(result.terminal_cmd)
    end)

    it("does not mutate defaults", function()
      config.apply({ port_range = { min = 50000 }, auto_start = false })
      assert.same({ min = 10000, max = 65535 }, config.defaults.port_range)
      assert.equals(true, config.defaults.auto_start)
    end)
  end)
end)
