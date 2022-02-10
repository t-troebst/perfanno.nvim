-- parse_perf.lua
-- This module provides wrappers around perf to generate our stack trace format.

local M = {}

-- Execute cmd and return the stdout result
local function get_command_output(cmd, silent)
    if silent then
        cmd = cmd .. " 2>/dev/null"
    end

    local data_file = assert(io.popen(cmd, "r"))
    data_file:flush()
    local output = data_file:read("*all")
    data_file:close()

    return output
end

-- Obtains simple flat profile from perf (no callgraph)
function M.perf_flat(perf_data)
    local esc = vim.fn.fnameescape(perf_data)
    local cmd = "perf report -g none -F sample,srcline --stdio --full-source-path -i " .. esc
    local raw_data = get_command_output(cmd, true)

    local result = {}
    local current_event

    for line in raw_data:gmatch("[^\r\n]+") do
        local num, event = line:match("# Samples: (%d+[KMB]?)%s+of event '(.*)'")

        if num and event then
            result[event] = {}
            current_event = event
        else
            local count, address = line:match("^%s*(%d+)%s+(.*[+:]%d+)")

            if count and address and tonumber(count) > 0 then
                table.insert(result[current_event], {count = tonumber(count), frames = {address}})
            end
        end
    end

    return result
end

-- Obtains actual stack traces from perf via the folded output mode
function M.perf_callgraph(perf_data)
    local esc = vim.fn.fnameescape(perf_data)
    local cmd = "perf report -g folded,0,caller,srcline,branch,count --no-children --full-source-path --stdio -i " .. esc
    local raw_data = get_command_output(cmd, true)

    local result = {}
    local current_event

    for line in raw_data:gmatch("[^\r\n]+") do
        local num, event = line:match("# Samples: (%d+[KMB]?)%s+of event '(.*)'")

        if num and event then
            result[event] = {}
            current_event = event
        else
            local count, traceline = line:match("^(%d+) (.*)$")

            if count and traceline and tonumber(count) > 0 then
                local tracedata = {count = tonumber(count), frames = {}}

                for func in traceline:gmatch("[^;]+") do
                    local file = func:match("(/.*:%d+)")

                    if file then
                        table.insert(tracedata.frames, file)
                    else -- address, symbol, etc. (no debug info)
                        table.insert(tracedata.frames, func)
                    end
                end

                table.insert(result[current_event], tracedata)
            end
        end
    end

    return result
end

return M
