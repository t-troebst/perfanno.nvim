--- Deals with core functionality: storing and and processing call graphs.

local util = require("perfanno.util")

local M = {}

--- Separates frame into symbol, file, and line number.
-- @param frame Either a string of the form "{symbol} {file}:{linenr}" where file is a full file
--        path, or a table with entries for symbol, file, and linenr.
-- @return symbol, file, line number File will be cleaned up into canonical
--         format. If we don't have both a file *and* a line number, return nil,
--         "symbol", symbol name instead.
local function frame_unpack(frame)
    if util.is_table(frame) then
        -- TODO: in some cases we might have a file but no line number
        if not frame.file or not frame.linenr then
            return nil, "symbol", frame.symbol
        end

        frame.file = vim.loop.fs_realpath(frame.file) or frame.file
        return frame.symbol, frame.file, frame.linenr
    end

    local symbol, file, linenr = frame:match("^(.-)%s*(/.+):(%d+)$")

    if symbol and file and linenr then
        if symbol == "" then
            symbol = nil
        end

        return symbol, vim.loop.fs_realpath(file), tonumber(linenr)
    end

    return nil, "symbol", frame
end

--- Processes a list of stack traces into the call graph information.
-- @param traces List of tables of the form {count = 15, frames = {f1, f2, f3, ...}}. The count
--        represents how many times this exact stack trace occurs and each frame should be in the
--        format expected by frame_unpack. See also :help perfanno-extensions.
-- @return node info, total count, max count, symbols
-- TODO: document more
local function process_traces(traces)
    local node_info = {symbol = {}}
    local total_count = 0
    local max_count = 0
    local symbols = {}

    for _, trace in ipairs(traces) do
        local visited_lines = {}  -- needed to get sane results with recursion
        local visited_symbols = {}  -- ditto

        total_count = total_count + trace.count

        -- Compute basic node counts for annotations.
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
                -- Symbol counts need to be done separately because of potential recursion.
                if not visited_symbols[{file, symbol}] then
                    visited_symbols[{file, symbol}] = true

                    util.init(symbols, file, {})
                    util.init(symbols[file], symbol, {count = 0, min_line = nil, max_line = nil})

                    symbols[file][symbol].count = symbols[file][symbol].count + trace.count
                end

                -- Useful to jump to the symbol later.
                symbols[file][symbol].min_line =
                    util.min_nil(symbols[file][symbol].min_line, linenr)
                symbols[file][symbol].max_line =
                    util.max_nil(symbols[file][symbol].min_line, linenr)
            end
        end

        local visited = {}

        -- Compute in / out neighbor counts for caller / callee lookup.
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

--- Merges the weighted in-degrees of nodes in the call graph.
-- @param event Event that selects which call graph we will use.
-- @param nodes List of {file, linenr} pairs.
-- @return Table result such that result[file][linenr] represents the amount of stack traces that go
--         through file:linenr right before they enter one of the given nodes.
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

--- Merges the weighted out-degrees of nodes in the call graph.
-- @param event Event that selects which call graph we will use.
-- @param nodes List of {file, linenr} pairs.
-- @return Table result such that result[file][linenr] represents the amount of stack traces that go
--         through file:linenr right after they leave one of the given nodes.
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

--- Loads given list of stack traces into call graph.
-- @param traces Stack traces to be loaded. For format see :help perfanno-extensions.
function M.load_traces(traces)
    M.events = {}
    M.callgraphs = {}

    for event, ts in pairs(traces) do
        table.insert(M.events, event)

        local ni, sy, tc, mc = process_traces(ts)
        M.callgraphs[event] = {node_info = ni, symbols = sy, total_count = tc, max_count = mc}
    end
end

--- Returns whether a suitable call graph is loaded.
-- @return true if callgraph is loaded for at least one event.
function M.is_loaded()
    if M.callgraphs and M.events and #M.events > 0 then
        return true
    end

    return false
end

--- Asserts whether call graph is loaded for given event.
-- @param event Event to check for.
function M.check_event(event)
    assert(M.is_loaded(), "Callgraph is not loaded!")
    assert(M.callgraphs[event], "Invalid event!")
end

return M
