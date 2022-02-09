# PerfAnno - Perf Profiling Annotations in NeoVim!

PerfAnno is a simple lua plugin for NeoVim that allows you to annotate your code with output from perf.
It supports two different modes:

* **callgraph:** Each line is annotated with the samples that occurred in that line *including* nested function calls. This requires that the perf.data file has been recorded with callgraph information.
* **flat:** Each line is annotated with the samples that occurred in that line *without* nested function calls.

If the perf.data file has multiple events, then you can choose which event you want to use for annotation.
In addition, PerfAnno provides a Telescope finder that allows you to immediately jump to the hottest lines in your code base.

![demo](https://user-images.githubusercontent.com/15610942/153112464-ebfee5f2-11c3-4185-ad96-2cf8e7f7cd42.gif)

**This demo is bound to be out of date compared to the current state of the plugin!**

## Installation

This plugin was tested on NeoVim 0.61 and perf 5.16.
The callgraph mode may require a relatively recent version of perf that supports folded output.
You should be able to install this plugin the same way you install other NeoVim lua plugins, e.g. via `use "t-troebst/perfanno.nvim"` in packer.
After installing, you can initialize the plugin by calling:

```lua
require("perfanno").setup {
    -- Colors to use to highlight hot lines
    -- I generated these with: https://meyerweb.com/eric/tools/color-blend
    colors = {"#46292F", "#672C23", "#892E18", "#AA310C", "#CC3300"},
    
    -- Highlights to use to highlight hot lines, overrides colors
    highlights = nil,
    
    -- Color (or highlight) to use for virtual text annotations
    -- You can set this to nil if you don't want virtual text
    virtual_text = {color = "#CC3300", highlight = nil},
    
    -- Changes how lines are annotated for flat and callgraph mode
    -- numbers: either "count" for sample counts or "percent" for (global) percentages
    -- format: how to format the line annotations, also used in the telescope finder
    -- mimimum: only annotate lines where the sample count / percentage is above this value
    flat_format = {numbers = "count", format = "%d", minimum = 1},
    callgraph_format = {numbers = "percent", format = "%.2f%%", minimum = 0.5},
}
```

**Note:** if you want to use the `:PerfAnnoFindHottest` command to jump to the hottest lines of code, you need to have [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) installed.

## Workflow

The typical workflow uses the following commands:

* `:PerfLoadFlat` loads flat perf data or `:PerfLoadCallGraph` loads full call graph perf data. If there is no `perf.data` file in your working directory, you will be asked to locate one.
* `:PerfToggleAnnotations` toggles annotations in all buffers assuming they have been loaded. If the perf data contains multiple events you will be asked to pick one the first time you use this command.
* `:PerfPickEvent` chooses a different event from the perf data.
* `:PerfHottest` opens a telescope finder with the hottest lines according to the current annotations.
* `:PerfHottestCallers` opens a telescope finder with the hottest lines that lead directly to the currently selected lines. Typically, you would select a function to see from where it gets called the most. However, you may also want to select a file, a class, or even specific lines.

## Future Goals

* Allow annotating relative to a certain area (function, block, selection, file, etc.)
* Make `:PerfHottestCallers` more convenient by automatically selecting functions with treesitter.
* Add `vim.ui.select` fallback option if telescope is not installed
* Show annotations inside the telescope previewer
* Add callgraph exploration via a very customized telescope finder
* All support for other profilers: we only need stack traces with source line information
