-- init.lua
-- Main entry point, defines nice wrappers for usability
local callgraph = require("perfanno.callgraph")
local parse_perf = require("perfanno.parse_perf")
local annotate = require("perfanno.annotate")
local util = require("perfanno.util")
local config = require("perfanno.config")
local telescope = require("perfanno.telescope")

local M = {}

function M.setup(opts)
    config.load(opts)

    -- TODO: switch to vim.api.nvim_add_user_command once its available
    vim.cmd[[command PerfLoadFlat :lua require("perfanno").load_perf_flat()]]
    vim.cmd[[command PerfLoadCallGraph :lua require("perfanno").load_perf_callgraph()]]
    vim.cmd[[command PerfPickEvent :lua require("perfanno").pick_event()]]
    vim.cmd[[command PerfAnnotate :lua require("perfanno").annotate()]]
    vim.cmd[[command PerfToggleAnnotations :lua require("perfanno").toggle_annotations()]]
    vim.cmd[[command PerfCycleFormat :lua require("perfanno").cycle_format()]]
    vim.cmd[[command PerfHottest :lua require("perfanno").find_hottest()]]
    vim.cmd[[command PerfHottestCallers :lua require("perfanno").find_hottest_callers()]]

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

function M.load_perf_flat()
    get_perf_data(function(perf_data)
        callgraph.load_traces(parse_perf.perf_flat(perf_data))

        if #callgraph.events == 1 then
            config.selected_event = callgraph.events[1]
        else
            config.selected_event = nil
        end

        if callgraph.is_loaded() and config.annotate_after_load then
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

        if callgraph.is_loaded() and config.annotate_after_load then
            M.annotate()
        end
    end)
end


function M.pick_event(cont)
    assert(callgraph.is_loaded(), "Callgraph must be loaded before we can pick an event!")

    vim.ui.select(callgraph.events, {prompt = "Select event type to annotate: "}, function(event)
        config.selected_event = event or config.selected_event

        if config.selected_event and cont then
            if annotate.is_toggled() then
                annotate.annotate()
            end

            cont()
        end
    end)
end

function M.with_event(cont)
    assert(callgraph.is_loaded(), "Callgraph must be loaded!")

    if config.selected_event and callgraph.callgraphs[config.selected_event] then
        cont(config.selected_event)
    else
        M.pick_event(cont)
    end
end

function M.annotate()
    M.with_event(function()
        if config.selected_event then
            annotate.annotate()
        end
    end)
end

function M.toggle_annotations()
    M.with_event(function()
        if config.selected_event then
            annotate.toggle_annotations()
        end
    end)
end

local function should_annotate()
    return callgraph.is_loaded() and config.selected_event and callgraph.callgraphs[config.selected_event] and annotate.is_toggled()
end

function M.cycle_format()
    config.selected_format = config.selected_format + 1

    if config.selected_format > table.getn(config.formats) then
        config.selected_format = 1
    end

    if should_annotate() then
        annotate.annotate()
    end
end

function M.try_annotate_current()
    if should_annotate() then
        annotate.annotate_buffer(vim.fn.bufnr("%"))
    end
end

function M.find_hottest()
    M.with_event(function(event)
        if event then
            telescope.find_hottest(event)
        end
    end)
end

function M.find_hottest_callers()
    M.with_event(function(event)
        if event then
            local file = vim.fn.expand("%:p")
            local line_begin, _, line_end, _ = util.visual_selection_range()

            telescope.find_hottest_callers(file, line_begin, line_end)
        end
    end)
end

return M
