--- Mock vim global for testing outside Neovim
--- This allows unit tests to run with busted standalone

local M = {}

-- Simple spy implementation
local function create_spy()
  local calls = {}
  local spy_mt = {
    __call = function(self, ...)
      table.insert(calls, { ... })
      if self._return_value ~= nil then
        return self._return_value
      end
      if self._return_fn then
        return self._return_fn(...)
      end
    end,
  }
  local spy = setmetatable({
    calls = calls,
    _return_value = nil,
    _return_fn = nil,
    returns = function(self, value)
      self._return_value = value
      return self
    end,
    returns_fn = function(self, fn)
      self._return_fn = fn
      return self
    end,
    called = function(self)
      return #self.calls > 0
    end,
    call_count = function(self)
      return #self.calls
    end,
    called_with = function(self, ...)
      local args = { ... }
      for _, call in ipairs(self.calls) do
        local match = true
        for i, arg in ipairs(args) do
          if call[i] ~= arg then
            match = false
            break
          end
        end
        if match then
          return true
        end
      end
      return false
    end,
    reset = function(self)
      for k in pairs(self.calls) do
        self.calls[k] = nil
      end
    end,
  }, spy_mt)
  return spy
end

M.create_spy = create_spy

-- Mock TCP handle
local function create_mock_tcp()
  local tcp = {
    _bound = false,
    _listening = false,
    _closed = false,
    _data_callback = nil,
    _write_buffer = {},
  }

  tcp.bind = create_spy():returns(0)
  tcp.listen = create_spy():returns(0)
  tcp.accept = create_spy():returns_fn(function()
    return create_mock_tcp()
  end)
  tcp.read_start = create_spy():returns_fn(function(_, callback)
    tcp._data_callback = callback
    return 0
  end)
  tcp.read_stop = create_spy():returns(0)
  tcp.write = create_spy():returns_fn(function(_, data, callback)
    table.insert(tcp._write_buffer, data)
    if callback then
      callback()
    end
  end)
  tcp.close = create_spy():returns_fn(function(_, callback)
    tcp._closed = true
    if callback then
      callback()
    end
  end)
  tcp.is_closing = create_spy():returns(false)
  tcp.getsockname = create_spy():returns({ ip = "127.0.0.1", port = 12345 })

  -- Helper to simulate receiving data
  tcp._receive = function(data)
    if tcp._data_callback then
      tcp._data_callback(nil, data)
    end
  end

  return tcp
end

M.create_mock_tcp = create_mock_tcp

-- Mock timer handle
local function create_mock_timer()
  local timer = {
    _running = false,
    _callback = nil,
  }

  timer.start = create_spy():returns_fn(function(_, timeout, repeat_ms, callback)
    timer._running = true
    timer._callback = callback
  end)
  timer.stop = create_spy():returns_fn(function()
    timer._running = false
  end)
  timer.close = create_spy()

  -- Helper to trigger the timer
  timer._trigger = function()
    if timer._callback then
      timer._callback()
    end
  end

  return timer
end

M.create_mock_timer = create_mock_timer

-- Setup mock vim global
function M.setup()
  -- Use cjson if available, otherwise simple implementation
  local json_encode, json_decode
  local ok, cjson = pcall(require, "cjson")
  if ok then
    json_encode = cjson.encode
    json_decode = cjson.decode
  else
    -- Minimal JSON implementation for testing
    json_encode = function(tbl)
      if type(tbl) == "string" then
        return '"' .. tbl:gsub('"', '\\"') .. '"'
      elseif type(tbl) == "number" or type(tbl) == "boolean" then
        return tostring(tbl)
      elseif type(tbl) == "nil" then
        return "null"
      elseif type(tbl) == "table" then
        local is_array = #tbl > 0 or next(tbl) == nil
        if is_array then
          local parts = {}
          for _, v in ipairs(tbl) do
            table.insert(parts, json_encode(v))
          end
          return "[" .. table.concat(parts, ",") .. "]"
        else
          local parts = {}
          for k, v in pairs(tbl) do
            table.insert(parts, '"' .. k .. '":' .. json_encode(v))
          end
          return "{" .. table.concat(parts, ",") .. "}"
        end
      end
      return "null"
    end
    json_decode = function(str)
      -- Very basic JSON decode - use cjson for real tests
      local fn = load("return " .. str:gsub("%[", "{"):gsub("%]", "}"):gsub("null", "nil"):gsub('":"', '"]=[['):gsub('","', ']],["'):gsub('"}', ']]}')):gsub('"{', '[[,{')
      if fn then
        return fn()
      end
      return nil
    end
  end

  _G.vim = {
    -- vim.fn functions
    fn = {
      expand = create_spy():returns_fn(function(path)
        if path == "~" or path:match("^~") then
          return "/home/testuser" .. path:sub(2)
        end
        return path
      end),
      mkdir = create_spy():returns(1),
      filereadable = create_spy():returns(1),
      readfile = create_spy():returns({}),
      getpid = create_spy():returns(12345),
      getcwd = create_spy():returns("/test/workspace"),
      has = create_spy():returns_fn(function(feature)
        if feature == "nvim-0.8.0" then
          return 1
        end
        return 0
      end),
    },

    -- vim.loop (libuv)
    loop = {
      new_tcp = create_spy():returns_fn(create_mock_tcp),
      new_timer = create_spy():returns_fn(create_mock_timer),
      hrtime = create_spy():returns_fn(function()
        return os.time() * 1000000000
      end),
    },

    -- vim.json
    json = {
      encode = json_encode,
      decode = json_decode,
    },

    -- vim.schedule
    schedule = function(fn)
      fn()
    end,
    schedule_wrap = function(fn)
      return fn
    end,

    -- vim.notify
    notify = create_spy(),

    -- vim.api
    api = {
      nvim_create_user_command = create_spy(),
      nvim_create_autocmd = create_spy():returns(1),
      nvim_create_augroup = create_spy():returns(1),
      nvim_echo = create_spy(),
      nvim_err_writeln = create_spy(),
      nvim_get_current_buf = create_spy():returns(1),
      nvim_buf_get_name = create_spy():returns("/test/file.lua"),
      nvim_list_bufs = create_spy():returns({ 1 }),
      nvim_buf_is_loaded = create_spy():returns(true),
      nvim_get_option_value = create_spy():returns(""),
    },

    -- vim.log.levels
    log = {
      levels = {
        ERROR = 1,
        WARN = 2,
        INFO = 3,
        DEBUG = 4,
        TRACE = 5,
      },
    },

    -- vim.inspect
    inspect = function(val, opts)
      if type(val) == "table" then
        local parts = {}
        for k, v in pairs(val) do
          table.insert(parts, tostring(k) .. " = " .. tostring(v))
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
      end
      return tostring(val)
    end,

    -- vim.deepcopy
    deepcopy = function(tbl)
      if type(tbl) ~= "table" then
        return tbl
      end
      local copy = {}
      for k, v in pairs(tbl) do
        copy[k] = _G.vim.deepcopy(v)
      end
      return copy
    end,

    -- vim.tbl_deep_extend
    tbl_deep_extend = function(behavior, ...)
      local result = {}
      for _, tbl in ipairs({ ... }) do
        for k, v in pairs(tbl) do
          if type(v) == "table" and type(result[k]) == "table" then
            result[k] = _G.vim.tbl_deep_extend(behavior, result[k], v)
          else
            result[k] = v
          end
        end
      end
      return result
    end,

    -- vim.version
    version = function()
      return { major = 0, minor = 10, patch = 0 }
    end,

    -- vim.lsp
    lsp = {
      get_clients = create_spy():returns({}),
      get_active_clients = create_spy():returns({}),
    },
  }

  return _G.vim
end

-- Reset all spies
function M.reset()
  if _G.vim then
    for _, group in pairs({ _G.vim.fn, _G.vim.loop, _G.vim.api }) do
      for _, fn in pairs(group) do
        if type(fn) == "table" and fn.reset then
          fn:reset()
        end
      end
    end
    if _G.vim.notify and _G.vim.notify.reset then
      _G.vim.notify:reset()
    end
  end
end

-- Teardown mock
function M.teardown()
  _G.vim = nil
end

return M
