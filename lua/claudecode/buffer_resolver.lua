---
-- Resolve attachable context from non-file buffers for ClaudeCode.nvim.
-- Turns the current buffer + cursor/visual-range into real file path(s) the
-- Claude CLI can read via at_mention; falls back to materializing the buffer
-- text into a temp file when no real file can be resolved.
-- @module claudecode.buffer_resolver
local M = {}

---@class ResolveOpts
---@field bufnr integer
---@field line1 integer|nil  -- 1-indexed visual range start (nil = cursor only)
---@field line2 integer|nil

---@class ResolveResult
---@field paths string[]
---@field source "adapter"|"cfile"|"lineparse"|"materialize"|nil
---@field error string|nil

-- ---- pure helpers ---------------------------------------------------------

local function git_root(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local start = (name ~= "" and vim.fs.dirname(name)) or vim.fn.getcwd()
  local found = vim.fs.find(".git", { path = start, upward = true })[1]
  return found and vim.fs.dirname(found) or vim.fn.getcwd()
end

--- Strip neogit/diff/grep/status prefixes, return the last path-ish token or nil.
local function strip_markers(line)
  line = line:gsub("^%s+", "")
  line = line:gsub("^[MADRCU%?!]+%s+", "") -- git status flags
  line = line:gsub("^%a+ file:%s*", "") -- "new file: ", "modified: "
  line = line:gsub("^[%-%+]%+%+ [ab]/", "") -- diff --- a/  +++ b/
  line = line:gsub("%s+%->%s+.*$", "") -- rename "old -> new" (keep old)
  local token = line:match("([%w%._%-/~]+%.%w+)") or line:match("([%w%._%-/~]+/[%w%._%-/]+)")
  return token
end

local function to_readable(token, root)
  if not token or token == "" then
    return nil
  end
  local abs = token
  if not abs:match("^/") then
    abs = root .. "/" .. token
  end
  abs = vim.fn.fnamemodify(abs, ":p")
  return (vim.fn.filereadable(abs) == 1) and abs or nil
end

local function dedup(paths)
  local seen, out = {}, {}
  for _, p in ipairs(paths) do
    if p and not seen[p] then
      seen[p] = true
      out[#out + 1] = p
    end
  end
  return out
end

local function config()
  local ok, claudecode = pcall(require, "claudecode")
  local state_config = ok and claudecode.state and claudecode.state.config or {}
  return state_config.buffer_resolver or {}
end

-- ---- step 1: plugin adapters ---------------------------------------------

local adapters = {}

adapters.NeogitStatus = function(bufnr)
  local ok, status = pcall(require, "neogit.buffers.status")
  if not ok then
    return nil
  end
  local inst = status.instance and status.instance()
  if not inst or not inst.buffer or not inst.buffer.ui then
    return nil
  end
  local ok2, rel = pcall(function()
    return inst.buffer.ui:get_filepaths_in_selection()
  end)
  if not ok2 or not rel or #rel == 0 then
    return nil
  end
  local root = git_root(bufnr)
  local out = {}
  for _, p in ipairs(rel) do
    out[#out + 1] = to_readable(p, root)
  end
  return dedup(out)
end

adapters.qf = function(_bufnr, line1, line2)
  local list = vim.fn.getqflist()
  if not list or #list == 0 then
    return nil
  end
  local lo = line1 or vim.api.nvim_win_get_cursor(0)[1]
  local hi = line2 or lo
  local out = {}
  for i = lo, hi do
    local item = list[i]
    if item and item.bufnr and item.bufnr > 0 then
      out[#out + 1] = vim.api.nvim_buf_get_name(item.bufnr)
    end
  end
  return dedup(out)
end

-- ---- step 2/3: cfile + generic line-parse --------------------------------

local function resolve_cfile(bufnr)
  local cfile = vim.fn.expand("<cfile>")
  if not cfile or cfile == "" then
    return nil
  end
  local hit = vim.fn.findfile(cfile, vim.bo[bufnr].path)
  if hit ~= "" then
    return { vim.fn.fnamemodify(hit, ":p") }
  end
  return nil
end

local function resolve_lineparse(bufnr, line1, line2)
  local lo = line1 or vim.api.nvim_win_get_cursor(0)[1]
  local hi = line2 or lo
  local lines = vim.api.nvim_buf_get_lines(bufnr, lo - 1, hi, false)
  local root = git_root(bufnr)
  local out = {}
  for _, l in ipairs(lines) do
    out[#out + 1] = to_readable(strip_markers(l), root)
  end
  out = dedup(out)
  return (#out > 0) and out or nil
end

-- ---- step 4: materialize (side effects) ----------------------------------

local cleanup_registered = false

local function scratch_dir()
  return config().scratch_dir or (vim.fn.stdpath("cache") .. "/claudecode/scratch")
end

local DIFFY = { git = true, diff = true, NeogitStatus = true, fugitive = true, fugitiveblame = true }

--- Dump the buffer (or range) text into a temp file and return its path.
---@param opts ResolveOpts
---@return string|nil path
function M.materialize(opts)
  local bufnr = opts.bufnr or 0
  local lo = opts.line1 and (opts.line1 - 1) or 0
  local hi = opts.line2 or -1
  local lines = vim.api.nvim_buf_get_lines(bufnr, lo, hi, false)

  local cap = config().max_materialize_lines or 5000
  if #lines > cap then
    lines = vim.list_slice(lines, 1, cap)
  end

  local dir = scratch_dir()
  vim.fn.mkdir(dir, "p")

  local ft = vim.bo[bufnr].filetype
  local base = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
  base = (base ~= "" and base) or (ft ~= "" and ft) or "buffer"
  base = base:gsub("[^%w%._%-]", "_")
  local ext = DIFFY[ft] and ".diff" or ".txt"
  local path = string.format("%s/claudecode-%s-%d%s", dir, base, bufnr, ext)

  if vim.fn.writefile(lines, path) ~= 0 then
    return nil
  end

  if not cleanup_registered then
    cleanup_registered = true
    vim.api.nvim_create_autocmd("VimLeavePre", {
      callback = function()
        pcall(vim.fn.delete, scratch_dir(), "rf")
      end,
    })
  end
  return path
end

-- ---- public entry ---------------------------------------------------------

--- Resolve attachable file path(s) from a non-file buffer.
---@param opts ResolveOpts
---@return ResolveResult
function M.resolve(opts)
  local bufnr = opts.bufnr or 0
  local cfg = config()
  if cfg.enabled == false then
    return { paths = {}, error = "buffer_resolver disabled" }
  end

  local ft = vim.bo[bufnr].filetype
  local steps = {
    {
      "adapter",
      function()
        local a = adapters[ft]
        return a and a(bufnr, opts.line1, opts.line2)
      end,
    },
    {
      "cfile",
      function()
        return resolve_cfile(bufnr)
      end,
    },
    {
      "lineparse",
      function()
        return resolve_lineparse(bufnr, opts.line1, opts.line2)
      end,
    },
  }
  for _, step in ipairs(steps) do
    local ok, paths = pcall(step[2])
    if ok and paths and #paths > 0 then
      return { paths = paths, source = step[1] }
    end
  end

  if cfg.materialize_fallback ~= false then
    local path = M.materialize(opts)
    if path then
      return { paths = { path }, source = "materialize" }
    end
  end
  return { paths = {}, error = "no file path resolved from buffer (filetype=" .. ft .. ")" }
end

-- Test helpers (exposed for testing)
M._strip_markers = strip_markers
M._to_readable = to_readable
M._dedup = dedup

return M
