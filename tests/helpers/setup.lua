-- Test environment setup

-- This function sets up the test environment
return function()
  -- Create mock vim API if we're running tests outside of Neovim
  if not vim then
    -- luacheck: ignore
    _G.vim = require("tests.mocks.vim")
  end

  -- Setup test globals
  _G.assert = require("luassert")
  _G.stub = require("luassert.stub")
  _G.spy = require("luassert.spy")
  _G.mock = require("luassert.mock")

  -- Helper function to verify a test passes
  _G.it = function(desc, fn)
    local ok, err = pcall(fn)
    if not ok then
      print("FAIL: " .. desc)
      print(err)
      error("Test failed: " .. desc)
    else
      print("PASS: " .. desc)
    end
  end

  -- Helper function to describe a test group
  _G.describe = function(desc, fn)
    print("\n==== " .. desc .. " ====")
    fn()
  end

  -- Helper to assert an expectation
  _G.expect = function(value)
    return {
      to_be = function(expected)
        assert.are.equal(expected, value)
      end,
      to_be_nil = function()
        assert.is_nil(value)
      end,
      to_be_true = function()
        assert.is_true(value)
      end,
      to_be_false = function()
        assert.is_false(value)
      end,
      to_be_table = function()
        assert.is_table(value)
      end,
      to_have_key = function(key)
        assert.is_table(value)
        assert.not_nil(value[key])
      end,
    }
  end

  -- Load the plugin under test
  package.loaded["claudecode"] = nil

  -- Return true to indicate setup was successful
  return true
end
