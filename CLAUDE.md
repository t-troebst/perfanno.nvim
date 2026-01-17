# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

perfanno.nvim is a Neovim plugin that displays profiling annotations (from `perf` or custom profilers) directly in the editor with interactive call graph exploration.

## Development Commands

```bash
# Format code (uses StyLua)
make format
# or: stylua lua/

# Run unit tests (requires plenary.nvim)
make test

# Test manually in Neovim
nvim --noplugin -u minimal_init.lua
```

## Code Style

- StyLua config: 100 column width, spaces for indentation, `call_parentheses = "NoSingleTable"`
- Pure Lua with Neovim API (no external build step)

## Architecture

```
init.lua (entry point, commands, autocmds)
    ↓
config.lua (user settings, format definitions)
    ↓
Data Sources:
  parse_perf.lua   → shells out to `perf report`, parses output
  lua_profile.lua  → LuaJIT profiler for Neovim itself
  load_traces()    → API for custom profilers
    ↓
callgraph.lua (CORE: processes traces into file→line→metadata structure)
    ↓
Presentation:
  annotate.lua           → extmarks, virtual text, highlights
  find_hottest.lua       → sorted hotspot tables, vim.ui.select fallback
  telescope/_extensions/ → Telescope pickers with preview annotation
  treesitter.lua         → function boundary detection
    ↓
cache.lua (JSON persistence of callgraphs)
```

## Key Globals

- `callgraph.callgraphs` / `callgraph.events` - current profiling data
- Uses Neovim namespaces for extmark isolation

## Testing

Tests use plenary.nvim's busted-style framework. Use canonical luassert assertion forms for lua_ls compatibility:

```lua
-- Use these canonical forms:
assert.are.equal(expected, actual)
assert.are.same(expected_table, actual_table)
assert.is_true(value)
assert.is_false(value)
assert.is_nil(value)

-- For error testing, use pcall:
local ok = pcall(some_function, arg)
assert.is_true(ok)   -- expect no error
assert.is_false(ok)  -- expect error

-- Avoid these (cause lua_ls warnings):
assert.equals(...)        -- use assert.are.equal
assert.has_no.errors(...) -- use pcall pattern
assert.has.errors(...)    -- use pcall pattern
```

## Extension API

Custom profilers integrate via:
```lua
require("perfanno").load_traces({ event_name = {{ count = N, frames = {...} }, ...} })
```
