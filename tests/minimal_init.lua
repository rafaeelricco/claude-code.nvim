--- Minimal init for running tests inside Neovim
--- Used with: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/"

-- Add the plugin to runtimepath
vim.opt.rtp:prepend(".")

-- Add plenary if available
local plenary_path = vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.rtp:prepend(plenary_path)
end

-- Alternative plenary paths
local alt_paths = {
  vim.fn.expand("~/.local/share/nvim/site/pack/packer/start/plenary.nvim"),
  vim.fn.expand("~/.local/share/nvim/site/pack/vendor/start/plenary.nvim"),
}

for _, path in ipairs(alt_paths) do
  if vim.fn.isdirectory(path) == 1 then
    vim.opt.rtp:prepend(path)
    break
  end
end

-- Disable swap files for testing
vim.opt.swapfile = false

-- Set test-friendly options
vim.opt.shortmess:append("I") -- No intro message
vim.opt.more = false -- No "-- More --" prompt

-- Helper function to run a single test file
_G.run_test_file = function(file)
  local ok, plenary = pcall(require, "plenary.busted")
  if ok then
    plenary.run(file)
  else
    print("plenary.nvim not found, using basic test runner")
    dofile(file)
  end
end
