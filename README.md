# PerfAnno - Profiling Annotations and Call Graph Exploration in NeoVim!

PerfAnno is a simple lua plugin for NeoVim that allows you to annotate your code with output from perf (or other profilers).
It supports two different modes:

* **call graph:** Each line is annotated with the samples that occurred in that line *including* nested function calls. This requires that the perf.data file has been recorded with call graph information.
* **flat:** Each line is annotated with the samples that occurred in that line *without* nested function calls. This information is easier to get but obviously disables some useful features of this plugin.

If the perf.data file has multiple events, then you can choose switch between the event you want to use for annotation.
In addition, PerfAnno provides a Telescope finder that allows you to immediately jump to the hottest lines in your code base or the hottest callers of a specific region of code (typically a function).

![demo](https://user-images.githubusercontent.com/15610942/153112464-ebfee5f2-11c3-4185-ad96-2cf8e7f7cd42.gif)

**This demo is currently out of date!**

## Installation

This plugin requires NeoVim 0.6 and was tested with perf 5.16.
The call graph mode may require a relatively recent version of perf that supports folded output, though it should be easy to add support for older versions similar to how flamegraph does it.

You should be able to install this plugin the same way you install other NeoVim lua plugins, e.g. via `use "t-troebst/perfanno.nvim"` in packer.
After installing, you can initialize the plugin by calling:

```lua
require("perfanno").setup {
    -- List of highlights that will be used to highlight hot lines (or nil to disable highlighting)
    line_highlights = nil,
    -- Highlight used for virtual text annotations (or nil to disable virtual text)
    vt_highlight = nil,

    -- Annotation formats that can be cycled between via :PerfCycleFormat
    --   "percent" controls whether percentages or absolute counts should be displayed
    --   "format" is the format string that will be used to display counts / percentages
    --   "minimum" is the minimum value below which lines will not be annotated
    -- Note: this also controls what shows up in the telescope finders
    formats = {
        {percent = true, format = "%.2f%%", minimum = 0.5},
        {percent = false, format = "%d", minimum = 1}
    },

    -- Automatically annotate files after :PerfLoadFlat and :PerfLoadCallGraph
    annotate_after_load = true,

    -- Node type patterns used to find the function that surrounds the cursor
    ts_function_patterns = {
        -- These should work for most languages (at least those used with perf)
        default = {
            "function",
            "method",
        },
        -- Otherwise you can add patterns for specific languages like:
        -- weirdlang = {
        --     "weirdfunc",
        -- }
    }
}

```

You will most likely want to set `line_highlights` and `vt_highlight` to appropriate highlights and set some keybindings to make use of this plugin.
For an example see the provided [example config](#example-config).

**Dependencies:**
If you want to use the `:PerfHottest` or `:PerfHottestSelectionCallers` commands to jump to the hottest lines of code, you need to have [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) installed.
For `:PerfHottestFunctionCallers` you will additionally need [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter).

## Example Config

The following config sets the highlights to a nice RGB color gradient between the background color and an orange red.
It also sets convenient keybindings for all of the standard commands.

```lua

local perfanno = require("perfanno")
local util = require("perfanno.util")

local bgcolor = vim.fn.synIDattr(vim.fn.hlID("Normal"), "bg", "gui")

perfanno.setup {
    line_highlights = util.make_bg_highlights(bgcolor, "#CC3300", 10),
    vt_highlight = util.make_fg_highlight("#CC3300"),
}

local keymap = vim.api.nvim_set_keymap

keymap("n", "<LEADER>plf", ":PerfLoadFlat<CR>", opts)
keymap("n", "<LEADER>plg", ":PerfLoadCallGraph<CR>", opts)
keymap("n", "<LEADER>pa", ":PerfAnnotate<CR>", opts)
keymap("n", "<LEADER>pe", ":PerfPickEvent<CR>", opts)
keymap("n", "<LEADER>pf", ":PerfCycleFormat<CR>", opts)
keymap("n", "<LEADER>pt", ":PerfToggleAnnotations<CR>", opts)
keymap("n", "<LEADER>ph", ":PerfHottest<CR>", opts)
keymap("n", "<LEADER>pc", ":PerfHottestFunctionCallers<CR>", opts)
keymap("v", "<LEADER>pc", ":PerfHottestSelectionCallers<CR>", opts)
```

## Workflow

The typical workflow uses the following commands:

* `:PerfLoadFlat` loads flat perf data or `:PerfLoadCallGraph` loads full call graph perf data. If there is no `perf.data` file in your working directory, you will be asked to locate one. If `annotate_after_load` is set this will immediately annotate all buffers.
* `:PerfToggleAnnotations` toggles annotations in all buffers assuming they have been loaded.
* `:PerfCycleFormat` allows you to toggle between the stored formats, by default this toggles between percentages and absolute counts.
* `:PerfPickEvent` chooses a different event from the perf data.
* `:PerfHottest` opens a telescope finder with the hottest lines according to the current annotations.
* `:PerfHottestSelectionCallers` opens a telescope finder with the hottest lines that lead directly to the currently selected lines. If you want to specifically select the current function, use `:PerfHottestFunctionCallers`.

## Future Goals

This plugin is still under **active development** as I plan to add various other features:

* Allow annotating relative to a selection or to the current function
* Show annotations inside the telescope previewer
* Add call graph exploration via a very customized telescope finder
* Add `vim.ui.select` fallback option if telescope is not installed
* Add support for other profilers: we only need stack traces with source line information
