# PerfAnno - Perf Profiling Annotations in NeoVim!

PerfAnno is a simple lua plugin for NeoVim that allows you to annotate your code with output from perf.
It supports two different modes:

* **callgraph:** Each line is annotated with the samples that occurred in that line *including* nested function calls. This requires that the perf.data file has been recorded with callgraph information.
* **flat:** Each line is annotated with the samples that occurred in that line *without* nested function calls.

If the perf.data file has multiple events, then you can choose which event you want to use for annotation.
In addition, PerfAnno provides a Telescope finder that allows you to immediately jump to the hottest lines in your code base.

![demo](https://user-images.githubusercontent.com/15610942/153112464-ebfee5f2-11c3-4185-ad96-2cf8e7f7cd42.gif)

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
    flat = {numbers = "count", format = "%d", minimum = 1},
    callgraph = {numbers = "percent", format = "%.2f%%", minimum = 0.5},
    
    -- Adds an auto command to annotate newly opened buffers if we have the data from perf
    auto_annotate = true,
}
```

**Note:** if you want to use the `:PerfAnnoFindHottest` command to jump to the hottest lines of code, you need to have [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) installed.
In the future, I plan to add a fallback option that uses `vim.ui.select`.

## Workflow

The typical workflow uses the following commands:

* `:PerfAnnoAnnotateFlat` loads flat perf data and annotates all buffers. If there is no `perf.data` file in your working directory, you will be asked to locate one. If there are multiple events in that file, you will also be asked which event to annotate.
* `:PerfAnnoAnnotateCallGraph` loads callgraph data and annotates all buffers. Works just like `:PerfAnnoAnnotateFlat`.
* `:PerfAnnoToggleAnnotations` toggles annotations assuming they have been loaded.
* `:PerfAnnoFindHottest` opens a telescope finder with the hottest files according to the current annotations.
