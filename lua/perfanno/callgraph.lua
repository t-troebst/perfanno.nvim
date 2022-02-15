-- callgraph.lua
-- This file deals with transforming stack traces into a callgraph to allow for the
-- core functionality of this plugin.

local util = require("perfanno.util")

local M = {}

local function frame_unpack(frame)
    if util.is_table(frame) then
        if not frame.file or not frame.linenr then
            return nil, "symbol", frame.symbol
        end

        return frame.symbol, frame.file, frame.linenr
    end

    local symbol, file, linenr = frame:match("^(.-)%s*(/.+):(%d+)$")

    if symbol and file and linenr then
        if symbol == "" then
            symbol = nil
        end

        return symbol, file, tonumber(linenr)
    end

    return nil, "symbol", frame
end

local function process_traces(traces)
    local node_info = {symbol = {}}
    local total_count = 0
    local max_count = 0
    local symbols = {}

    -- Compute basic node counts for annotations
    for _, trace in ipairs(traces) do
        local visited_lines = {} -- needed to get sane results with recursion
        local visited_symbols = {}

        total_count = total_count + trace.count

        for _, frame in ipairs(trace.frames) do
            local symbol, file, linenr = frame_unpack(frame)

            if not visited_lines[{file, linenr}] then
                visited_lines[{file, linenr}] = true

                util.init(node_info, file, {})
                util.init(node_info[file], linenr, {count = 0, out_counts = {}, in_counts = {}})

                node_info[file][linenr].count = node_info[file][linenr].count + trace.count
                max_count = math.max(max_count, node_info[file][linenr].count)
            end

            if symbol then
                if not visited_symbols[file .. ":" .. symbol] then
                    visited_symbols[file .. ":" .. symbol] = true

                    util.init(symbols, file, {})
                    util.init(symbols[file], symbol, {count = 0, min_line = nil, max_line = nil})

                    symbols[file][symbol].count = symbols[file][symbol].count + trace.count
                end

                symbols[file][symbol].min_line = util.min_nil(symbols[file][symbol].min_line, linenr)
                symbols[file][symbol].max_line = util.max_nil(symbols[file][symbol].min_line, linenr)
            end
        end

        local visited = {}

        -- Compute in / out neighbor counts for caller / callee lookup
        for frame1, frame2 in util.pairwise(trace.frames) do
            if not visited[{frame1, frame2}] then
                table.insert(visited, {frame1, frame2})
                local _, file1, linenr1 = frame_unpack(frame1)
                local _, file2, linenr2 = frame_unpack(frame2)

                util.init(node_info[file1][linenr1].out_counts, file2, {})
                util.init(node_info[file1][linenr1].out_counts[file2], linenr2, 0)
                node_info[file1][linenr1].out_counts[file2][linenr2] =
                    node_info[file1][linenr1].out_counts[file2][linenr2] + trace.count

                util.init(node_info[file2][linenr2].in_counts, file1, {})
                util.init(node_info[file2][linenr2].in_counts[file1], linenr1, 0)
                node_info[file2][linenr2].in_counts[file1][linenr1] =
                    node_info[file2][linenr2].in_counts[file1][linenr1] + trace.count
            end
        end
    end

    return node_info, symbols, total_count, max_count
end

function M.merge_in_counts(event, nodes)
    local result = {}

    for _, node in ipairs(nodes) do
        for file, file_tbl in pairs(M.callgraphs[event].node_info[node[1]][node[2]].in_counts) do
            for linenr, count in pairs(file_tbl) do
                util.init(result, file, {})
                util.init(result[file], linenr, 0)

                result[file][linenr] = result[file][linenr] + count
            end
        end
    end

    return result
end

function M.merge_out_counts(event, nodes)
    local result = {}

    for _, node in ipairs(nodes) do
        for file, file_tbl in pairs(M.callgraphs[event].node_info[node[1]][node[2]].out_counts) do
            for linenr, count in pairs(file_tbl) do
                util.init(result, file, {})
                util.init(result[file], linenr, 0)

                result[file][linenr] = result[file][linenr] + count
            end
        end
    end

    return result
end

function M.load_traces(traces)
    M.events = {}
    M.callgraphs = {}

    for event, ts in pairs(traces) do
        table.insert(M.events, event)

        local ni, sy, tc, mc = process_traces(ts)
        M.callgraphs[event] = {node_info = ni, symbols = sy, total_count = tc, max_count = mc}
    end
end

function M.is_loaded()
    if M.callgraphs and M.events and #M.events > 0 then
        return true
    end

    return false
end

return M
