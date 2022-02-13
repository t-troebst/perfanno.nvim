# PerfAnno: Profiling Annotations and Call Graph Exploration in NeoVim!

PerfAnno is a simple lua plugin for NeoVim that allows you to annotate your code with output from perf or potentially other profilers.
It supports two different modes:

* **call graph:** Each line is annotated with the samples that occurred in that line *including* nested function calls. This requires that the perf.data file has been recorded with call graph information.
* **flat:** Each line is annotated with the samples that occurred in that line *without* nested function calls. This information is easier to get but obviously disables some useful features of this plugin.

If the perf.data file has multiple events such as, say, cpu cycles, branch mispredictions and cache misses, then you can switch between these.
In addition, PerfAnno provides a Telescope (or `vim.ui.select`) finder that allows you to immediately jump to the hottest lines in your code base or the hottest callers of a specific region of code (typically a function).

![demo](https://user-images.githubusercontent.com/15610942/153376301-d096ae61-e6a3-46f3-a8b1-305bd0007d7a.gif)

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
    -- Automatically annoate newly opened buffers if information is available
    annotate_on_open = true,

    -- Options for telescope-based hottest line finders
    telescope = {
        -- Enable if possible, otherwise the plugin will fall back to vim.ui.select
        enabled = pcall(require, "telescope"),
        -- Annotate inside of the preview window
        annotate = true,
    },

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

These are the default settings, so this is equivalent to `require("perfanno").setup()`.
You will most likely want to set `line_highlights` and `vt_highlight` to appropriate highlights and set some keybindings to make use of this plugin.
See the provided [example config](#example-config).

**Dependencies:**
If you want to use the commands that jump to the hottest lines of code, you will probably want to have [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) installed.
Otherwise (or if you explicitly disable telescope during setup), the plugin will fall back to `vim.ui.select` instead.
For `:PerfAnnotateFunction` and `:PerfHottestCallersFunction` you will need [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter).

## Example Config

The following config sets the highlights to a nice RGB color gradient between the background color and an orange red.
It also sets convenient keybindings for all of the standard commands.

```lua

local perfanno = require("perfanno")
local util = require("perfanno.util")

local bgcolor = vim.fn.synIDattr(vim.fn.hlID("Normal"), "bg", "gui")

perfanno.setup {
    -- Creates a 10-step RGB color gradient beween bgcolor and "#CC3300"
    line_highlights = util.make_bg_highlights(bgcolor, "#CC3300", 10),
    vt_highlight = util.make_fg_highlight("#CC3300"),
}

local keymap = vim.api.nvim_set_keymap

keymap("n", "<LEADER>plf", ":PerfLoadFlat<CR>", opts)
keymap("n", "<LEADER>plg", ":PerfLoadCallGraph<CR>", opts)

keymap("n", "<LEADER>pe", ":PerfPickEvent<CR>", opts)
keymap("n", "<LEADER>pf", ":PerfCycleFormat<CR>", opts)

keymap("n", "<LEADER>pa", ":PerfAnnotate<CR>", opts)
keymap("n", "<LEADER>paf", ":PerfAnnotateFunction<CR>", opts)
keymap("v", "<LEADER>pa", ":PerfAnnotateSelection<CR>", opts)

keymap("n", "<LEADER>pt", ":PerfToggleAnnotations<CR>", opts)

keymap("n", "<LEADER>ph", ":PerfHottestLines<CR>", opts)
keymap("n", "<LEADER>pc", ":PerfHottestCallersFunction<CR>", opts)
keymap("v", "<LEADER>pc", ":PerfHottestCallersSelection<CR>", opts)
```

## Workflow

The typical workflow uses the following commands:

### Load profiling data

* `:PerfLoadFlat` loads flat perf data. Obviously you will not be able to find callers of functions in this mode.
* `:PerfLoadCallGraph` loads full call graph perf data. This may take a while.

If there is no `perf.data` file in your working directory, you will be asked to locate one. If `annotate_after_load` is set this will immediately annotate all buffers.

### Control how annotations are displayed

* `:PerfPickEvent` chooses a different event from the perf data to display. For example, you could use this to switch between cpu cycles, branch mispredictions, and cache misses.
* `:PerfCycleFormat` allows you to toggle between the stored formats, by default this toggles between percentages and absolute counts.

### Annotate

* `:PerfAnnotate` annotates all currently open buffers.
* `:PerfToggleAnnotations` toggles annotations in all buffers.
* `:PerfAnnotateSelection` annotates code only in a given selection. Line highlights are shown relative to the total counts in that selection and if the current format is in percent, then the displayed percentages are also relative.
* `:PerfAnnotateFunction` does the same as `:PerfAnnotateSelection` but selects the function that contains the cursor via treesitter.

If there is more than one event that was loaded, then you will be asked to pick one before annotations can be displayed.

### Find hot lines

* `:PerfHottestLines` opens a telescope finder with the hottest lines according to the current annotations.
* `:PerfHottestCallersSelection` opens a telescope finder with the hottest lines that lead directly to the currently selected lines.
* `:PerfHottestCallersFunction` works just like `:PerfHottestCallersSelection` but selects the function that contains the cursor via treesitter.

## Future Goals

* Improve (or rather add...) documentation
* Improve the robustness of `:PerfCycleFormat` (it currently resets relative annotations and it doesn't work inside an active telescope finder)
* Add some kind of tree-based call graph exploration
