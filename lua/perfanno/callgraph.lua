-- callgraph.lua
-- This file deals with transforming stack traces into a callgraph to allow for the
-- core functionality of this plugin.

local util = require("perfanno.util")

local M = {}

local function frame_index(frame)
    local file, linenr = frame:match("^(/.+):(%d+)$")

    if file and linenr then
        return file, tonumber(linenr)
    else
        return "symbol", frame
    end
end

local function process_traces(traces)
    local node_info = {}
    local total_count = 0
    local max_count = 0

    -- Compute basic node counts for annotations
    for _, trace in ipairs(traces) do
        local visited = {} -- needed to get sane results with recursion

        total_count = total_count + trace.count

        for _, frame in ipairs(trace.frames) do
            if not visited[frame] then
                table.insert(visited, frame)
                local file, linenr = frame_index(frame)

                util.init(node_info, file, {})
                util.init(node_info[file], linenr, {count = 0, out_counts = {}, in_counts = {}})

                node_info[file][linenr].count = node_info[file][linenr].count + trace.count
                max_count = math.max(max_count, node_info[file][linenr].count)
            end
        end

        visited = {}

        -- Compute in / out neighbor counts for caller / callee lookup
        for frame1, frame2 in util.pairwise(trace.frames) do
            if not visited[{frame1, frame2}] then
                table.insert(visited, {frame1, frame2})
                local file1, linenr1 = frame_index(frame1)
                local file2, linenr2 = frame_index(frame2)

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

    return node_info, total_count, max_count
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

        local ni, tc, mc = process_traces(ts)
        M.callgraphs[event] = {node_info = ni, total_count = tc, max_count = mc}
    end
end

function M.is_loaded()
    return M.callgraphs ~= nil and M.events ~= nil and #M.events > 0
end

return M
