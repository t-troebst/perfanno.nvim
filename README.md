# PerfAnno: Profiling Annotations and Call Graph Exploration in NeoVim!

PerfAnno is a simple lua plugin for NeoVim that allows you to annotate your code with output from perf or other call graph profilers that can generate stack traces in the [flamegraph](https://github.com/brendangregg/FlameGraph) format.
The plugin itself is language agnostic and has been tested with C, C++, Lua, and Python. PerfAno can be used to [profile neovim itself easily](#lua-profiling).

Each line is annotated with the samples that occurred in that line *including* nested function calls. This requires that the perf.data file has been recorded with call graph information.
If the profiler provides multiple events such as, say, cpu cycles, branch mispredictions and cache misses, then you can switch between these.
In addition, PerfAnno provides a Telescope (or `vim.ui.select`) finder that allows you to immediately jump to the hottest lines / functions in your code base or the hottest callers of a specific region of code (typically a function).

https://user-images.githubusercontent.com/15610942/153775719-ed236a8d-d012-448d-b3b1-8b38f57d1fbf.mp4

## Installation

This plugin requires NeoVim 0.7 and was tested most recently with NeoVim 0.10 and perf 5.16.
The call graph mode may require a relatively recent version of perf that supports folded output, though it should be easy to add support for older versions manually.

You should be able to install this plugin the same way you install other NeoVim lua plugins, e.g. via `use "t-troebst/perfanno.nvim"` in packer.
After installing, you need to initialize the plugin by calling:
```lua
require("perfanno").setup()
```

This will give you the default settings which are shown [below](#configuration).
However, you may want to set `line_highlights` and `vt_highlight` to appropriate highlights that do not clash with your color scheme and set some keybindings to make use of this plugin.
See the provided [example config](#example-config).

**Dependencies:**
If you want to use the commands that jump to the hottest lines of code, you will probably want to have [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) installed.
Otherwise (or if you explicitly disable telescope during setup), the plugin will fall back to `vim.ui.select` instead.
For `:PerfAnnotateFunction` and `:PerfHottestCallersFunction` you will need [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter).

## Example Config

The following config sets the highlights to a nice RGB color gradient between the background color and an orange red.
It also sets convenient keybindings for most of the standard commands.

```lua
local perfanno = require("perfanno")
local util = require("perfanno.util")

perfanno.setup {
    -- Creates a 10-step RGB color gradient beween background color and "#CC3300"
    line_highlights = util.make_bg_highlights(nil, "#CC3300", 10),
    vt_highlight = util.make_fg_highlight("#CC3300"),
}

local keymap = vim.api.nvim_set_keymap
local opts = {noremap = true, silent = true}

keymap("n", "<LEADER>plf", ":PerfLoadFlat<CR>", opts)
keymap("n", "<LEADER>plg", ":PerfLoadCallGraph<CR>", opts)
keymap("n", "<LEADER>plo", ":PerfLoadFlameGraph<CR>", opts)

keymap("n", "<LEADER>pe", ":PerfPickEvent<CR>", opts)

keymap("n", "<LEADER>pa", ":PerfAnnotate<CR>", opts)
keymap("n", "<LEADER>pf", ":PerfAnnotateFunction<CR>", opts)
keymap("v", "<LEADER>pa", ":PerfAnnotateSelection<CR>", opts)

keymap("n", "<LEADER>pt", ":PerfToggleAnnotations<CR>", opts)

keymap("n", "<LEADER>ph", ":PerfHottestLines<CR>", opts)
keymap("n", "<LEADER>ps", ":PerfHottestSymbols<CR>", opts)
keymap("n", "<LEADER>pc", ":PerfHottestCallersFunction<CR>", opts)
keymap("v", "<LEADER>pc", ":PerfHottestCallersSelection<CR>", opts)
```

## Configuration

For the full list of potential configuration options, see the following setup call.

```lua
require("perfanno").setup {
    -- List of highlights that will be used to highlight hot lines (or nil to disable).
    line_highlights = require("perfanno.util").make_bg_highlights(nil, "#FF0000", 10),
    -- Highlight used for virtual text annotations (or nil to disable virtual text).
    vt_highlight = require("perfanno.util").make_fg_highlight("#FF0000"),

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
    -- Automatically annotate newly opened buffers if information is available
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

local telescope = require("telescope")
local actions = telescope.extensions.perfanno.actions
telescope.setup {
    extensions = {
        perfanno = {
            -- Special mappings in the telescope finders
            mappings = {
                ["i"] = {
                    -- Find hottest callers of selected entry
                    ["<C-h>"] = actions.hottest_callers,
                    -- Find hottest callees of selected entry
                    ["<C-l>"] = actions.hottest_callees,
                },

                ["n"] = {
                    ["gu"] = actions.hottest_callers,
                    ["gd"] = actions.hottest_callees,
                }
            }
        }
    }
}
```

These are the default settings, so this is equivalent to `require("perfanno").setup()`.

## Workflow

In order to use this plugin, you will need to generate accurate profiling information with perf, ideally with call graph information.
You will want to compile your program with debug information and then run:

`perf record --call-graph dwarf {program}`

This will then generate a `perf.data` file that can be used by this plugin.
From there you can use the commands shown [below](#commands).
If the `dwarf` option creates files that are too large or take too long to process, you may also want to try:

`perf record --call-graph fp {program}`

However, this requires that your program and all libraries have been compiled with `-fno-omit-frame-pointer` and you may find that the line numbers are slightly off.
For more information, see the documentation of perf.

If you are using another profiler, you will need to generate a `perf.log` file that stores data in the flamegraph format, i.e. as a list of `;`-separated stack traces with a count at the end in each line.
For example:

```
/path/to/src_1.cpp:30;/path/to/src_2.cpp:27;/path/to/src_1.cpp:27 47
/path/to/src_1.cpp:30;/path/to/src_2.cpp:50 20
/path/to/src_1.cpp:10;/path/to/src_3.cpp:20;/path/to/src_2.cpp:15 7
/path/to/src_1.cpp:10;/path/to/src_3.cpp:20;/path/to/src_2.cpp:50 92
```

## Commands

### Load profiling data

* `:PerfLoadFlat` loads flat perf data. Obviously you will not be able to find callers of functions in this mode.
* `:PerfLoadCallGraph` loads full call graph perf data. This may take a while.
* `:PerfLoadFlameGraph` loads data from a `perf.log` file in flamegraph format.

If there is no `perf.data` or `perf.log` file respectively in your working directory, you will be asked to locate one. If `annotate_after_load` is set this will immediately annotate all buffers.

### Lua Profiling

PerfAnno can be used to easily profile NeoVim via the native LuaJIT profiler.
Simply use the following commands in order:

* `:PerfLuaProfileStart` starts profiling.
* `:PerfLuaProfileStop` stops the current profiling run and loads the stack traces into the call
  graph. Automatically annotates all buffers if `annotate_after_load` is set.

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
* `:PerfHottestSymbols` opens a telescope finder with the hottest symbols (i.e. functions typically) according to the current annotations.
* `:PerfHottestCallersSelection` opens a telescope finder with the hottest lines that lead directly to the currently selected lines.
* `:PerfHottestCallersFunction` works just like `:PerfHottestCallersSelection` but selects the function that contains the cursor via treesitter.

### Caching (experimental)

Depending on how the callgraph is loaded, it may take a substantial amount of time to generate
(e.g. with perf on a long run) or it may not even be possible to generate it again (e.g. with the
Lua profiler). For these reasons, PerfAnno supports the ability to save/restore callgraphs to a
cache via the following commands:

* `:PerfCacheSave <name> ` saves the currently loaded callgraph in the cache under the given name.
* `:PerfCacheLoad <name>` loads the callgraph in the cache of the given name. Automatically
  annotates all buffers if `annotate_after_load` is set. If an empty name is supplied, the most
  recently cached callgraph is loaded.
* `:PerfCacheDelete <name>` deletes the callgraph in the cache of the given name.

## Extensions

If you wish to use this plugin with a profiler that is not perf, you can simply call `require("perfanno").load_traces` to set up the callgraph information with a list of stack traces for each possible event.
For the exact format see the example below.

```lua
local traces = {
    "event 1" = {
       {
           count = 42,
           frames = {
                "symbol1 /home/user/Project/src_1.cpp:57",
                "symbol2 /home/user/Project/src_2.cpp:32",
                "symbol1 /home/user/Project/src_1.cpp:42"
           }
       },
       {
           count = 99,
           frames = {
                "symbol3 /home/user/Project/src_1.cpp:20",
                "0x1231232",
                "__foo_bar",
                "symbol4 /home/user/Project/src_3.cpp:50"
           }
       },
       -- more traces...
    },

    "event 2" = {
        -- ...
    },

    -- more events...
}

require("perfanno").load_traces(traces)
```

A stack trace is represented by a `count` which tells us how often that exact trace occurred and a list of `frames`.
Each stack frame should start with a `symbol` followed by `fullpath`:`linenum`.
If it does not fit into this format, it will simply be interpreted as an arbitrary symbol.
You may also specify a frame directly in the format:

```lua
{symbol = "symbol1", file = "/home/user/Project/src_1.cpp", linenr = 42}
```

Note: The file paths in the traces should be full, unescaped paths in the canonical format, i.e. `/full/file path/to/source.cpp:35` instead of `/full/file\ path//to/../to/source.cpp:35`.
We try to get canonical representations of the paths but this is generally most reliable.

## Future Goals

* Add telescope finder to load / delete callgraphs from the cache.
* Improve the robustness of `:PerfCycleFormat` (it currently resets relative annotations and it doesn't work inside an active telescope finder).
* Add support for `:FindHottestCallers` with increased depth.
* Add `:FindHottestCallees` which is essentially `:FindHottestLines` but relative to stack traces that go through a certain selection.
