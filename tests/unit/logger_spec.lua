--- Tests for lua/claudecode/logger.lua

if not vim then
  require("tests.helpers.mock_vim").setup()
end

describe("logger", function()
  local logger
  local captured_notifications
  local original_notify

  before_each(function()
    package.loaded["claudecode.logger"] = nil
    logger = require("claudecode.logger")

    captured_notifications = {}
    original_notify = vim.notify
    vim.notify = function(message, level)
      table.insert(captured_notifications, { message = message, level = level })
    end
  end)

  after_each(function()
    vim.notify = original_notify
  end)

  describe("logger behavior", function()
    it("filters enabled levels from configured log_level", function()
      logger.setup({ log_level = "info" })

      assert.is_true(logger.is_level_enabled("error"))
      assert.is_true(logger.is_level_enabled("warn"))
      assert.is_true(logger.is_level_enabled("info"))
      assert.is_false(logger.is_level_enabled("debug"))
      assert.is_false(logger.is_level_enabled("trace"))
    end)

    it("falls back to info for invalid log_level", function()
      logger.setup({ log_level = "invalid" })

      assert.is_true(logger.is_level_enabled("info"))
      assert.is_false(logger.is_level_enabled("debug"))
      assert.equals(1, #captured_notifications)
    end)
  end)
end)
