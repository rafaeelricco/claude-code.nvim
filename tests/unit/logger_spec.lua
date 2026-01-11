--- Tests for lua/claudecode/logger.lua
--- Centralized logging functionality

-- Setup mock vim if not in Neovim
if not vim then
  require("tests.helpers.mock_vim").setup()
end

describe("logger", function()
  local logger
  local original_notify
  local captured_notifications

  before_each(function()
    -- Clear module cache
    package.loaded["claudecode.logger"] = nil
    package.loaded["claudecode.config"] = nil

    -- Capture notifications without depending on spy methods
    captured_notifications = {}
    original_notify = vim.notify

    vim.notify = function(msg, level, opts)
      table.insert(captured_notifications, { msg = msg, level = level, opts = opts })
    end

    logger = require("claudecode.logger")
  end)

  after_each(function()
    -- Restore original notify
    if original_notify then
      vim.notify = original_notify
    end
  end)

  describe("levels", function()
    it("has ERROR level", function()
      assert.is_number(logger.levels.ERROR)
    end)

    it("has WARN level", function()
      assert.is_number(logger.levels.WARN)
    end)

    it("has INFO level", function()
      assert.is_number(logger.levels.INFO)
    end)

    it("has DEBUG level", function()
      assert.is_number(logger.levels.DEBUG)
    end)

    it("has TRACE level", function()
      assert.is_number(logger.levels.TRACE)
    end)

    it("levels are ordered correctly", function()
      assert.is_true(logger.levels.ERROR < logger.levels.WARN)
      assert.is_true(logger.levels.WARN < logger.levels.INFO)
      assert.is_true(logger.levels.INFO < logger.levels.DEBUG)
      assert.is_true(logger.levels.DEBUG < logger.levels.TRACE)
    end)
  end)

  describe("setup", function()
    it("accepts valid log_level", function()
      -- Should not throw
      logger.setup({ log_level = "debug" })
    end)

    it("accepts all valid log levels", function()
      local valid_levels = { "error", "warn", "info", "debug", "trace" }
      for _, level in ipairs(valid_levels) do
        logger.setup({ log_level = level })
      end
    end)

    it("defaults to INFO for invalid level", function()
      -- Should not throw, but will notify
      logger.setup({ log_level = "invalid" })
    end)

    it("defaults to INFO for nil config", function()
      -- Should not throw
      logger.setup(nil)
    end)
  end)

  describe("is_level_enabled", function()
    it("returns true for enabled levels", function()
      logger.setup({ log_level = "info" })

      assert.is_true(logger.is_level_enabled("error"))
      assert.is_true(logger.is_level_enabled("warn"))
      assert.is_true(logger.is_level_enabled("info"))
    end)

    it("returns false for disabled levels", function()
      logger.setup({ log_level = "info" })

      assert.is_false(logger.is_level_enabled("debug"))
      assert.is_false(logger.is_level_enabled("trace"))
    end)

    it("returns false for invalid level name", function()
      assert.is_false(logger.is_level_enabled("invalid"))
    end)

    it("respects debug level setting", function()
      logger.setup({ log_level = "debug" })

      assert.is_true(logger.is_level_enabled("debug"))
      assert.is_false(logger.is_level_enabled("trace"))
    end)

    it("respects trace level setting", function()
      logger.setup({ log_level = "trace" })

      assert.is_true(logger.is_level_enabled("trace"))
    end)

    it("respects error level setting", function()
      logger.setup({ log_level = "error" })

      assert.is_true(logger.is_level_enabled("error"))
      assert.is_false(logger.is_level_enabled("warn"))
      assert.is_false(logger.is_level_enabled("info"))
    end)
  end)

  describe("log functions", function()
    it("has error function", function()
      assert.is_function(logger.error)
    end)

    it("has warn function", function()
      assert.is_function(logger.warn)
    end)

    it("has info function", function()
      assert.is_function(logger.info)
    end)

    it("has debug function", function()
      assert.is_function(logger.debug)
    end)

    it("has trace function", function()
      assert.is_function(logger.trace)
    end)

    it("error accepts component and message", function()
      -- Should not throw
      logger.error("test", "Test message")
    end)

    it("error accepts message without component", function()
      -- Should not throw
      logger.error("Test message without component")
    end)

    it("warn accepts component and message", function()
      logger.warn("test", "Test warning")
    end)

    it("info accepts component and message", function()
      logger.info("test", "Test info")
    end)

    it("debug accepts component and message", function()
      logger.setup({ log_level = "debug" })
      logger.debug("test", "Test debug")
    end)

    it("trace accepts component and message", function()
      logger.setup({ log_level = "trace" })
      logger.trace("test", "Test trace")
    end)

    it("handles multiple message parts", function()
      -- Should not throw
      logger.info("test", "Part 1", "Part 2", "Part 3")
    end)

    it("handles table in message", function()
      -- Should not throw
      logger.info("test", "Message with table:", { key = "value" })
    end)

    it("handles boolean in message", function()
      -- Should not throw
      logger.info("test", "Boolean value:", true)
    end)

    it("handles nil in message", function()
      -- Should not throw
      logger.info("test", "Nil value:", nil)
    end)
  end)
end)
