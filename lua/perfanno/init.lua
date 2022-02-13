-- Main entry point, defines nice wrappers for usability

local callgraph = require("perfanno.callgraph")
local parse_perf = require("perfanno.parse_perf")
local annotate = require("perfanno.annotate")
local config = require("perfanno.config")
local finder -- either telescope or vim.ui.select

local M = {}

function M.setup(opts)
    config.load(opts)

    -- Commands for loading call graph information via perf
    vim.cmd[[command PerfLoadFlat :lua require("perfanno").load_perf_flat()]]
    vim.cmd[[command PerfLoadCallGraph :lua require("perfanno").load_perf_callgraph()]]

    -- Commands that control what and how to annotate
    vim.cmd[[command PerfPickEvent :lua require("perfanno").pick_event()]]
    vim.cmd[[command PerfCycleFormat :lua require("perfanno").cycle_format()]]

    -- Commands that perform annotations
    vim.cmd[[command PerfAnnotate :lua require("perfanno").annotate()]]
    vim.cmd[[command PerfToggleAnnotations :lua require("perfanno").toggle_annotations()]]
    vim.cmd[[command PerfAnnotateFunction :lua require("perfanno").annotate_function()]]
    vim.cmd[[command -range PerfAnnotateSelection :lua require("perfanno").annotate_selection()]]

    -- Commands that find hot code lines
    vim.cmd[[command PerfHottestLines :lua require("perfanno").find_hottest_lines()]]
    vim.cmd[[command PerfHottestCallersFunction :lua require("perfanno").find_hottest_callers_function()]]
    vim.cmd[[command -range PerfHottestCallersSelection :lua require("perfanno").find_hottest_callers_selection()]]

    if config.values.telescope.enabled then
        finder = require("telescope").extensions.perfanno
    else
        finder = require("perfanno.find_hottest")
    end

    -- Setup automatic annotation of new buffers
    if config.values.annotate_on_open then
        vim.cmd[[autocmd BufRead * :lua require("perfanno").try_annotate_current()]]
    end
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

function M.load_perf_flat()
    get_perf_data(function(perf_data)
        callgraph.load_traces(parse_perf.perf_flat(perf_data))

        if #callgraph.events == 1 then
            config.selected_event = callgraph.events[1]
        else
            config.selected_event = nil
        end

        if callgraph.is_loaded() and config.values.annotate_after_load then
            M.annotate()
        end
    end)
end

function M.load_perf_callgraph()
    get_perf_data(function(perf_data)
        callgraph.load_traces(parse_perf.perf_callgraph(perf_data))

        if #callgraph.events == 1 then
            config.selected_event = callgraph.events[1]
        else
            config.selected_event = nil
        end

        if callgraph.is_loaded() and config.values.annotate_after_load then
            M.annotate()
        end
    end)
end

function M.pick_event(cont)
    assert(callgraph.is_loaded(), "Callgraph must be loaded before we can pick an event!")

    vim.ui.select(callgraph.events, {prompt = "Select event type to annotate: "}, function(event)
        config.selected_event = event or config.selected_event

        if config.selected_event then
            if annotate.is_toggled() then
                annotate.annotate()
            end

            if cont then
                cont()
            end
        end
    end)
end

function M.with_event(cont)
    assert(callgraph.is_loaded(), "Callgraph must be loaded!")

    if config.selected_event and callgraph.callgraphs[config.selected_event] then
        cont()
    else
        M.pick_event(cont)
    end
end

function M.annotate()
    M.with_event(annotate.annotate)
end

function M.toggle_annotations()
    M.with_event(annotate.toggle_annotations)
end

function M.annotate_function()
    M.with_event(annotate.annotate_function)
end

function M.annotate_selection()
    M.with_event(annotate.annotate_selection)
end

function M.cycle_format()
    config.selected_format = config.selected_format + 1

    if config.selected_format > #config.values.formats then
        config.selected_format = 1
    end

    if annotate.should_annotate() then
        annotate.annotate()
    end
end

function M.try_annotate_current()
    if annotate.should_annotate() then
        annotate.annotate_buffer()
    end
end

function M.find_hottest_lines()
    M.with_event(finder.find_hottest_lines)
end

function M.find_hottest_callers_function()
    M.with_event(finder.find_hottest_callers_function)
end

function M.find_hottest_callers_selection()
    M.with_event(finder.find_hottest_callers_selection)
end

return M
