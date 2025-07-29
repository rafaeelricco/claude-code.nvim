-- Luacheck configuration for Claude Code Neovim plugin

-- Set global variable names
globals = {
	"vim",
	"expect",
	"assert_contains",
	"assert_not_contains",
	"spy", -- For luassert.spy and spy.any
}

-- Ignore warnings for unused self parameters
self = false

-- Allow trailing whitespace
ignore = {
	"212/self", -- Unused argument 'self'
	"631", -- Line contains trailing whitespace
}

-- Set max line length
max_line_length = 120

-- Allow using external modules
allow_defined_top = true
allow_defined = true

-- Enable more checking
std = "luajit+busted"

-- Ignore tests/ directory for performance
exclude_files = {
	"tests/mocks",
}

