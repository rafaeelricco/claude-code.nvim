--- Tests for lua/claudecode/config.lua
--- Configuration validation and application

-- Setup mock vim if not in Neovim
if not vim then
  require("tests.helpers.mock_vim").setup()
end

describe("config", function()
  local config

  before_each(function()
    package.loaded["claudecode.config"] = nil
    config = require("claudecode.config")
  end)

  describe("defaults", function()
    it("has port_range with min and max", function()
      assert.is_table(config.defaults.port_range)
      assert.is_number(config.defaults.port_range.min)
      assert.is_number(config.defaults.port_range.max)
    end)

    it("has valid default port range", function()
      assert.is_true(config.defaults.port_range.min > 0)
      assert.is_true(config.defaults.port_range.max <= 65535)
      assert.is_true(config.defaults.port_range.min <= config.defaults.port_range.max)
    end)

    it("has auto_start boolean", function()
      assert.is_boolean(config.defaults.auto_start)
    end)

    it("has log_level string", function()
      assert.is_string(config.defaults.log_level)
    end)

    it("has valid default log_level", function()
      local valid_levels = { "trace", "debug", "info", "warn", "error" }
      local found = false
      for _, level in ipairs(valid_levels) do
        if config.defaults.log_level == level then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)
  end)

  describe("validate", function()
    it("accepts valid configuration", function()
      local valid_config = {
        port_range = { min = 10000, max = 65535 },
        auto_start = true,
        log_level = "info",
      }
      assert.is_true(config.validate(valid_config))
    end)

    it("accepts all valid log levels", function()
      local valid_levels = { "trace", "debug", "info", "warn", "error" }
      for _, level in ipairs(valid_levels) do
        local valid_config = {
          port_range = { min = 10000, max = 65535 },
          auto_start = true,
          log_level = level,
        }
        assert.is_true(config.validate(valid_config))
      end
    end)

    it("accepts auto_start as false", function()
      local valid_config = {
        port_range = { min = 10000, max = 65535 },
        auto_start = false,
        log_level = "info",
      }
      assert.is_true(config.validate(valid_config))
    end)

    it("accepts minimum valid port range", function()
      local valid_config = {
        port_range = { min = 1, max = 1 },
        auto_start = true,
        log_level = "info",
      }
      assert.is_true(config.validate(valid_config))
    end)

    it("accepts maximum valid port range", function()
      local valid_config = {
        port_range = { min = 65535, max = 65535 },
        auto_start = true,
        log_level = "info",
      }
      assert.is_true(config.validate(valid_config))
    end)

    -- Port range validation errors
    it("rejects port_range as nil", function()
      local invalid_config = {
        port_range = nil,
        auto_start = true,
        log_level = "info",
      }
      assert.has_error(function()
        config.validate(invalid_config)
      end, "Invalid port range")
    end)

    it("rejects port_range as non-table", function()
      local invalid_config = {
        port_range = "10000-65535",
        auto_start = true,
        log_level = "info",
      }
      assert.has_error(function()
        config.validate(invalid_config)
      end, "Invalid port range")
    end)

    it("rejects port_range with missing min", function()
      local invalid_config = {
        port_range = { max = 65535 },
        auto_start = true,
        log_level = "info",
      }
      assert.has_error(function()
        config.validate(invalid_config)
      end, "Invalid port range")
    end)

    it("rejects port_range with missing max", function()
      local invalid_config = {
        port_range = { min = 10000 },
        auto_start = true,
        log_level = "info",
      }
      assert.has_error(function()
        config.validate(invalid_config)
      end, "Invalid port range")
    end)

    it("rejects port_range with non-number min", function()
      local invalid_config = {
        port_range = { min = "10000", max = 65535 },
        auto_start = true,
        log_level = "info",
      }
      assert.has_error(function()
        config.validate(invalid_config)
      end, "Invalid port range")
    end)

    it("rejects port_range with non-number max", function()
      local invalid_config = {
        port_range = { min = 10000, max = "65535" },
        auto_start = true,
        log_level = "info",
      }
      assert.has_error(function()
        config.validate(invalid_config)
      end, "Invalid port range")
    end)

    it("rejects port_range with min <= 0", function()
      local invalid_config = {
        port_range = { min = 0, max = 65535 },
        auto_start = true,
        log_level = "info",
      }
      assert.has_error(function()
        config.validate(invalid_config)
      end, "Invalid port range")
    end)

    it("rejects port_range with negative min", function()
      local invalid_config = {
        port_range = { min = -1, max = 65535 },
        auto_start = true,
        log_level = "info",
      }
      assert.has_error(function()
        config.validate(invalid_config)
      end, "Invalid port range")
    end)

    it("rejects port_range with max > 65535", function()
      local invalid_config = {
        port_range = { min = 10000, max = 65536 },
        auto_start = true,
        log_level = "info",
      }
      assert.has_error(function()
        config.validate(invalid_config)
      end, "Invalid port range")
    end)

    it("rejects port_range with min > max", function()
      local invalid_config = {
        port_range = { min = 65535, max = 10000 },
        auto_start = true,
        log_level = "info",
      }
      assert.has_error(function()
        config.validate(invalid_config)
      end, "Invalid port range")
    end)

    -- auto_start validation errors
    it("rejects auto_start as nil", function()
      local invalid_config = {
        port_range = { min = 10000, max = 65535 },
        auto_start = nil,
        log_level = "info",
      }
      assert.has_error(function()
        config.validate(invalid_config)
      end, "auto_start must be a boolean")
    end)

    it("rejects auto_start as string", function()
      local invalid_config = {
        port_range = { min = 10000, max = 65535 },
        auto_start = "true",
        log_level = "info",
      }
      assert.has_error(function()
        config.validate(invalid_config)
      end, "auto_start must be a boolean")
    end)

    it("rejects auto_start as number", function()
      local invalid_config = {
        port_range = { min = 10000, max = 65535 },
        auto_start = 1,
        log_level = "info",
      }
      assert.has_error(function()
        config.validate(invalid_config)
      end, "auto_start must be a boolean")
    end)

    -- log_level validation errors
    it("rejects invalid log_level", function()
      local invalid_config = {
        port_range = { min = 10000, max = 65535 },
        auto_start = true,
        log_level = "invalid",
      }
      assert.has_error(function()
        config.validate(invalid_config)
      end)
    end)

    it("rejects log_level as number", function()
      local invalid_config = {
        port_range = { min = 10000, max = 65535 },
        auto_start = true,
        log_level = 1,
      }
      assert.has_error(function()
        config.validate(invalid_config)
      end)
    end)

    it("rejects log_level with wrong case", function()
      local invalid_config = {
        port_range = { min = 10000, max = 65535 },
        auto_start = true,
        log_level = "INFO",
      }
      assert.has_error(function()
        config.validate(invalid_config)
      end)
    end)

    it("rejects log_level as nil", function()
      local invalid_config = {
        port_range = { min = 10000, max = 65535 },
        auto_start = true,
        log_level = nil,
      }
      assert.has_error(function()
        config.validate(invalid_config)
      end)
    end)
  end)

  describe("apply", function()
    it("returns defaults when user_config is nil", function()
      local result = config.apply(nil)
      assert.same(config.defaults.port_range, result.port_range)
      assert.equals(config.defaults.auto_start, result.auto_start)
      assert.equals(config.defaults.log_level, result.log_level)
    end)

    it("returns defaults when user_config is empty table", function()
      local result = config.apply({})
      assert.same(config.defaults.port_range, result.port_range)
      assert.equals(config.defaults.auto_start, result.auto_start)
      assert.equals(config.defaults.log_level, result.log_level)
    end)

    it("overrides log_level only", function()
      local result = config.apply({ log_level = "debug" })
      assert.same(config.defaults.port_range, result.port_range)
      assert.equals(config.defaults.auto_start, result.auto_start)
      assert.equals("debug", result.log_level)
    end)

    it("overrides auto_start only", function()
      local result = config.apply({ auto_start = false })
      assert.same(config.defaults.port_range, result.port_range)
      assert.equals(false, result.auto_start)
      assert.equals(config.defaults.log_level, result.log_level)
    end)

    it("overrides port_range only", function()
      local result = config.apply({ port_range = { min = 20000, max = 30000 } })
      assert.same({ min = 20000, max = 30000 }, result.port_range)
      assert.equals(config.defaults.auto_start, result.auto_start)
      assert.equals(config.defaults.log_level, result.log_level)
    end)

    it("overrides port_range.min only", function()
      local result = config.apply({ port_range = { min = 20000 } })
      assert.equals(20000, result.port_range.min)
      assert.equals(config.defaults.port_range.max, result.port_range.max)
    end)

    it("overrides port_range.max only", function()
      local result = config.apply({ port_range = { max = 30000 } })
      assert.equals(config.defaults.port_range.min, result.port_range.min)
      assert.equals(30000, result.port_range.max)
    end)

    it("applies full custom configuration", function()
      local custom = {
        port_range = { min = 50000, max = 60000 },
        auto_start = false,
        log_level = "error",
      }
      local result = config.apply(custom)
      assert.same({ min = 50000, max = 60000 }, result.port_range)
      assert.equals(false, result.auto_start)
      assert.equals("error", result.log_level)
    end)

    it("throws error for invalid user config", function()
      assert.has_error(function()
        config.apply({ port_range = { min = 0, max = 65535 } })
      end, "Invalid port range")
    end)

    it("does not modify defaults table", function()
      local original_min = config.defaults.port_range.min
      local original_max = config.defaults.port_range.max
      local original_auto_start = config.defaults.auto_start
      local original_log_level = config.defaults.log_level

      config.apply({ port_range = { min = 50000, max = 60000 }, auto_start = false, log_level = "error" })

      assert.equals(original_min, config.defaults.port_range.min)
      assert.equals(original_max, config.defaults.port_range.max)
      assert.equals(original_auto_start, config.defaults.auto_start)
      assert.equals(original_log_level, config.defaults.log_level)
    end)

    it("returns a new table each time", function()
      local result1 = config.apply(nil)
      local result2 = config.apply(nil)
      assert.is_not.equals(result1, result2)
    end)

    it("ignores unknown configuration keys", function()
      local result = config.apply({ unknown_key = "value", another_unknown = 123 })
      assert.is_nil(result.unknown_key)
      assert.is_nil(result.another_unknown)
      -- But default values should still be present
      assert.same(config.defaults.port_range, result.port_range)
    end)
  end)
end)
