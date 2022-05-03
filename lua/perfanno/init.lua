-- Main entry point, defines nice wrappers for usability.

local config = require("perfanno.config")

local M = {}

--- Sets up the plugin with the provided options.
-- @param opt Options for the plugin. See :help perfanno-configuration.
function M.setup(opts)
    opts = opts or {}
    config.load(opts)

    -- Commands for loading call graph information via perf / flamegraph.
    vim.cmd[[command PerfLoadFlat :lua require("perfanno").load_perf_flat()]]
    vim.cmd[[command PerfLoadCallGraph :lua require("perfanno").load_perf_callgraph()]]
    vim.cmd[[command PerfLoadFlameGraph :lua require("perfanno").load_flamegraph()]]

    -- Lua profiling via the internal LuaJit profiler
    vim.cmd[[command PerfLuaProfileStart :lua require("perfanno").lua_profile_start()]]
    vim.cmd[[command PerfLuaProfileStop :lua require("perfanno").lua_profile_stop()]]

    -- Commands that control what and how to annotate.
    vim.cmd[[command PerfPickEvent :lua require("perfanno").pick_event()]]
    vim.cmd[[command PerfCycleFormat :lua require("perfanno").cycle_format()]]

    -- Commands that perform annotations.
    vim.cmd[[command PerfAnnotate :lua require("perfanno").annotate()]]
    vim.cmd[[command PerfToggleAnnotations :lua require("perfanno").toggle_annotations()]]
    vim.cmd[[command PerfAnnotateFunction :lua require("perfanno").annotate_function()]]
    vim.cmd[[command -range PerfAnnotateSelection :lua require("perfanno").annotate_selection()]]

    -- Commands that find hot code lines.
    vim.cmd[[command PerfHottestSymbols :lua require("perfanno").find_hottest_symbols()]]
    vim.cmd[[command PerfHottestLines :lua require("perfanno").find_hottest_lines()]]
    vim.cmd[[command PerfHottestCallersFunction :lua require("perfanno").find_hottest_callers_function()]]
    vim.cmd[[command -range PerfHottestCallersSelection :lua require("perfanno").find_hottest_callers_selection()]]

    -- Setup automatic annotation of new buffers.
    if config.values.annotate_on_open then
        vim.cmd[[autocmd BufRead * :lua require("perfanno").try_annotate_current()]]
    end
end

--- Checks if a file exists, if not asks the user, finally gives result to continuation.
-- @param default Default file such as "perf.data" to look for.
-- @param cont Continuation that will be called if the user selects a file.
local function get_data_file(default, cont)
    if vim.fn.filereadable(default) == 1 then
        cont(default)
    else
        local input_opts = {
            prompt = "Input path to " .. default .. ": ",
            default = vim.fn.getcwd() .. "/",
            completion = "file"
        }

        vim.ui.input(input_opts, function(file)
            if not file then
                return
            end

            if vim.fn.filereadable(file) == 0 then
                vim.notify("Could not read file!")
                return
            end

            cont(file)
        end)
    end
end

--- Loads stack traces in our format (see :help perfanno-extensions) into the callgraph.
-- Note: if enabled via the config, this also annotates all buffers.
-- @param traces Stack traces to load.
function M.load_traces(traces)
    local callgraph = require("perfanno.callgraph")
    callgraph.load_traces(traces)

    if callgraph.is_loaded() and config.values.annotate_after_load then
        M.annotate()
    end
end

--- Loads perf data into the call graph *without* call graph information (flat).
function M.load_perf_flat()
    get_data_file("perf.data", function(perf_data)
        M.load_traces(require("perfanno.parse_perf").perf_flat(perf_data))
    end)
end

--- Loads perf data into the call graph *with* call graph information.
function M.load_perf_callgraph()
    get_data_file("perf.data", function(perf_data)
        M.load_traces(require("perfanno.parse_perf").perf_callgraph(perf_data))
    end)
end

--- Parses a file containing stack traces in the flamegraph.pl format.
-- @param perf_log File to parse.
local function parse_flamegraph(perf_log)
    local traces = {}

    for line in io.lines(perf_log) do
        local trace = {}

        trace.count = line:match("(%d+)$")
        trace.frames = {}

        for frame in line:gmatch(";?(.-:%d+)") do
            table.insert(trace.frames, frame)
        end

        table.insert(traces, trace)
    end

    return {time = traces}
end

--- Loads flamegraph file into the call graph.
function M.load_flamegraph()
    get_data_file("perf.log", function(perf_log)
        M.load_traces(parse_flamegraph(perf_log))
    end)
end

--- Starts a LuaJIT profiling run (just a wrapper for consistency).
function M.lua_profile_start()
    require("perfanno.lua_profile").start()
end

--- Stops the current LuaJIT profiling run and annotates if annotate_after_load is set.
function M.lua_profile_stop()
    require("perfanno.lua_profile").stop()
    local callgraph = require("perfanno.callgraph")

    if callgraph.is_loaded() and config.values.annotate_after_load then
        M.annotate()
    end
end

--- Asks the user to pick a new event from the availabe options.
-- @param cont Continuation that gets executed if we have a valid event afterwards.
function M.pick_event(cont)
    local callgraph = require("perfanno.callgraph")

    if not callgraph.is_loaded() then
        vim.notify("No callgraph has been loaded!")
        return
    end

    local new_cont = function()
        local annotate = require("perfanno.annotate")

        if annotate.is_toggled() then
            annotate.annotate()
        end

        if cont then
            cont()
        end
    end

    if #callgraph.events == 1 then
        config.selected_event = callgraph.events[1]
        new_cont()
    else
        vim.ui.select(callgraph.events, {prompt = "Select event type to annotate: "}, function(event)
            config.selected_event = event or config.selected_event
            new_cont()
        end)
    end
end

--- Helper that calls a continuation with the current event, if possible, or asks user for one.
-- @param cont Continuation that will be called if we get a valid event.
function M.with_event(cont)
    local callgraph = require("perfanno.callgraph")

    if not callgraph.is_loaded() then
        vim.notify("No callgraph has been loaded!")
        return
    end

    if config.selected_event and callgraph.callgraphs[config.selected_event] then
        cont()
    else
        M.pick_event(cont)
    end
end

--- Annotates all buffers.
function M.annotate()
    M.with_event(require("perfanno.annotate").annotate)
end

--- Toggles annotations in all buffers.
function M.toggle_annotations()
    M.with_event(require("perfanno.annotate").toggle_annotations)
end

--- Annotates the function that contains the cursor.
function M.annotate_function()
    M.with_event(require("perfanno.annotate").annotate_function)
end

--- Annotates the current visual selection.
function M.annotate_selection()
    M.with_event(require("perfanno.annotate").annotate_selection)
end

--- Cycles between the different formats (see config), usually percentage and absolute counts.
function M.cycle_format()
    config.selected_format = config.selected_format + 1

    if config.selected_format > #config.values.formats then
        config.selected_format = 1
    end

    local annotate = require("perfanno.annotate")

    if annotate.should_annotate() then
        annotate.annotate()
    end
end

--- Annotate the current buffer if possible and annotations aren't toggled off.
function M.try_annotate_current()
    local annotate = require("perfanno.annotate")

    if annotate.should_annotate() then
        annotate.annotate_buffer()
    end
end

--- Returns perfanno telescope extension, or fallback module if that is unavailable / disabled.
local function finder()
    if config.values.telescope.enabled then
        return require("telescope").extensions.perfanno
    else
        return require("perfanno.find_hottest")
    end
end

--- Opens finder with the hottest symbols (functions) in the project for the current event.
function M.find_hottest_symbols()
    M.with_event(finder().find_hottest_symbols)
end

--- Opens finder with the hottest lines of code in the project for the current event.
function M.find_hottest_lines()
    M.with_event(finder().find_hottest_lines)
end

--- Opens finder with the hottest callers of the function that contains the cursor.
function M.find_hottest_callers_function()
    M.with_event(finder().find_hottest_callers_function)
end

--- Opens finder with the hottest callers of the current visual selection.
function M.find_hottest_callers_selection()
    M.with_event(finder().find_hottest_callers_selection)
end

return M
