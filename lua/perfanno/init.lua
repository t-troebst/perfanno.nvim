-- init.lua
-- Main entry point, defines nice wrappers for usability
local callgraph = require("perfanno.callgraph")
local parse_perf = require("perfanno.parse_perf")
local annotate = require("perfanno.annotate")
local telescope = require("perfanno.telescope")

local M = {}

-- Default highlights were generated with this tool:
-- https://meyerweb.com/eric/tools/color-blend/#24273B:CC3300:4:hex
-- This blends between the TokyoNight background and a nice red
local defaults = {
    colors = {"#46292F", "#672C23", "#892E18", "#AA310C", "#CC3300"},
    highlights = nil,
    virtual_text = {color = "#CC3300", highlight = nil},
    flat_format = {numbers = "count", format = "%d", minimum = 1},
    callgraph_format = {numbers = "percent", format = "%.2f%%", minimum = 0.5},
}

local opts

function M.setup(setup_opts)
    if setup_opts then
        opts = vim.tbl_deep_extend("force", defaults, setup_opts)
    end

    -- Create highlight for virtual text if a color was given
    if opts.virtual_text and not opts.virtual_text.highlight then
        opts.virtual_text.highlight = "PerfAnnoVT"
        vim.highlight.create("PerfAnnoVT", {guifg = opts.virtual_text.color}, false)
    end

    -- Create background highlights if colors were given
    if opts.colors and not opts.highlights then
        opts.highlights = {}

        for i, color in ipairs(opts.colors) do
            vim.highlight.create("PerfAnno" .. i, {guibg = color}, false)
            table.insert(opts.highlights, "PerfAnno" .. i)
        end
    end

    -- TODO: switch to vim.api.nvim_add_user_command once its available
    vim.cmd[[command PerfLoadFlat :lua require("perfanno").load_perf_flat()]]
    vim.cmd[[command PerfLoadCallGraph :lua require("perfanno").load_perf_callgraph()]]
    vim.cmd[[command PerfPickEvent :lua require("perfanno").pick_event()]]
    vim.cmd[[command PerfAnnotate :lua require("perfanno").annotate()]]
    vim.cmd[[command PerfToggleAnnotations :lua require("perfanno").toggle_annotations()]]
    vim.cmd[[command PerfHottest :lua require("perfanno").find_hottest()]]

    -- Setup automatic annotation of new buffers
    vim.cmd[[autocmd BufRead * :lua require("perfanno").try_annotate_current()]]
end

local function get_perf_data(cont)
    if vim.fn.filereadable("perf.data") == 1 then
        cont("perf.data")
    else
        local input_opts = {
            prompt = "Input path to perf.data: ",
            default = vim.fn.getcwd() .. "/",
            completion = "file"
        }

        vim.ui.input(input_opts, cont)
    end
end

local anno_opts
local current_event

function M.load_perf_flat()
    get_perf_data(function(perf_data)
        callgraph.load_traces(parse_perf.perf_flat(perf_data))

        anno_opts = {
            highlights = opts.highlights,
            virtual_text = opts.virtual_text,
            numbers = opts.flat_format.numbers,
            format = opts.flat_format.format,
            minimum = opts.flat_format.minimum,
        }

        if #callgraph.events == 1 then
            current_event = callgraph.events[1]
        end
    end)
end

function M.load_perf_callgraph()
    get_perf_data(function(perf_data)
        callgraph.load_traces(parse_perf.perf_callgraph(perf_data))

        anno_opts = {
            highlights = opts.highlights,
            virtual_text = opts.virtual_text,
            numbers = opts.callgraph_format.numbers,
            format = opts.callgraph_format.format,
            minimum = opts.callgraph_format.minimum
        }

        if #callgraph.events == 1 then
            current_event = callgraph.events[1]
        end
    end)
end


local function pick_event(cont)
    vim.ui.select(callgraph.events, {prompt = "Select event type to annotate: "}, function(event)
        current_event = event

        if event then
            cont(event)
        end
    end)
end

function M.with_event(cont)
    if current_event then
        cont(current_event)
    else
        pick_event(cont)
    end
end

function M.pick_event()
    assert(callgraph.is_loaded(), "Callgraph must be loaded before we can pick an event!")

    pick_event(function() end)
end

function M.annotate()
    assert(anno_opts, "You must use load_perf_flat() or load_perf_callgraph() first!")

    M.with_event(function(event)
        if event then
            annotate.annotate(event, anno_opts)
        end
    end)
end

function M.toggle_annotations()
    assert(anno_opts, "You must use load_perf_flat() or load_perf_callgraph() first!")

    M.with_event(function(event)
        if event then
            annotate.toggle_annotations(event, anno_opts)
        end
    end)
end

function M.try_annotate_current()
    if not anno_opts or not current_event or not annotate.is_toggled() then
        return
    end

    annotate.annotate_buffer(vim.fn.bufnr("%"), current_event, anno_opts)
end

function M.find_hottest()
    assert(anno_opts, "You must use load_perf_flat() or load_perf_callgraph() first!")

    M.with_event(function(event)
        if event then
            telescope.find_hottest(event, anno_opts)
        end
    end)
end

return M
