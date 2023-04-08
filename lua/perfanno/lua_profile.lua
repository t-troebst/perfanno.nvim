--- Uses the inbuilt LuaJit profiler to populate the callgraph.

local profile = require("jit.profile")
local callgraph = require("perfanno.callgraph")

local M = {}

local traces
local running = false

--- Callback that will be called on each sample of the profiler, collects stack traces.
-- @param thread Representation of the current call stack.
-- @param samples Number of samples since the last call (should be 1).
local function callback(thread, samples)
    local trace = {count = samples, frames = {}}
    local sdump = profile.dumpstack(thread, "f|pl;", 100)  -- TODO: make this configurable

    for symbol, location in sdump:gmatch("(.-)|(.-);") do
        if symbol:find(":") then
            symbol = nil
        end

        local file, linenr = location:match("(.-):(%d+)")

        if file and linenr then
            linenr = tonumber(linenr)
        else
            file = nil
            linenr = nil
        end

        table.insert(trace.frames, {symbol = symbol, file = file, linenr = linenr})
    end

    table.insert(traces, trace)
end

--- Start profiling.
-- @param sampling_interval Sampling interval in milliseconds.
function M.start(sampling_interval)
    if running then
        vim.notify("The profiler is already running - stop it first!", vim.log.levels.ERROR)
        return
    end

    sampling_interval = 10 or sampling_interval

    traces = {}
    running = true
    profile.start("li" .. sampling_interval, callback)
end


--- Stops profiling and loads the current traces into the call graph.
function M.stop()
    if not running then
        vim.notify("The profiler is not running - start it first!", vim.log.levels.ERROR)
        return
    end

    running = false
    profile.stop()
    callgraph.load_traces{time = traces}
end

--- Profiles a single function call and loads the resulting stack traces into the call graph.
-- @param expr Either a Lua function or a string that should be executed.
-- @param sampling_interval Sampling interval in milliseconds.
function M.profile(expr, sampling_interval)
    if type(expr) == "string" then
        expr = load(expr)
    end

    M.start(sampling_interval)
    expr()
    M.stop()
end

return M
