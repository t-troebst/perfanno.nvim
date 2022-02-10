-- telescope.lua
-- Telescope picker to find hottest lines in the code base

local p_ok, pickers = pcall(require, "telescope.pickers")
local f_ok, finders = pcall(require, "telescope.finders")
local c_ok, tconf = pcall(require, "telescope.config")

if not (p_ok and f_ok and c_ok) then
    return
end

tconf = tconf.values

local callgraph = require("perfanno.callgraph")
local config = require("perfanno.config")

local M = {}

local function hottest_table(nodes, total_count)
    local opts = {}

    opts.results = nodes

    table.sort(opts.results, function(e1, e2)
        return e1[3] > e2[3]
    end)

    opts.entry_maker = function(entry)
        local fmt = config.format(entry[3], total_count)

        if not fmt then
            return
        end

        if entry[1] == "symbol" then
            return {
                lnum = 0,
                display = fmt .. " " .. entry[2],
                ordinal = entry[2],
                path = "",
                row = 0,
                col = 0,
            }
        end

        local short_path = vim.fn.fnamemodify(entry[1], ":~:.")

        return {
            lnum = entry[2],
            display = fmt .. " " .. short_path .. ":" .. entry[2],
            ordinal = short_path .. ":" .. entry[2],
            path = entry[1],
            row = entry[2],
            col = 0
        }
    end

    return finders.new_table(opts)
end


function M.find_hottest(event, opts)
    assert(callgraph.is_loaded(), "Callgraph is not loaded!")
    event = event or config.selected_event
    assert(callgraph.callgraphs[event], "Invalid event!")

    local nodes = {}

    for file, file_tbl in pairs(callgraph.callgraphs[event].node_info) do
        for linenr, node_info in pairs(file_tbl) do
            table.insert(nodes, {file, linenr, node_info.count})
        end
    end

    opts = opts or {}

    pickers.new(opts, {
        prompt_title = "",
        finder = hottest_table(nodes, callgraph.callgraphs[event].total_count),
        sorter = tconf.file_sorter(opts),
        previewer = tconf.grep_previewer(opts)
    }):find()
end

function M.find_hottest_callers(file, line_begin, line_end, event, opts)
    assert(callgraph.is_loaded(), "Callgraph is not loaded!")
    event = event or config.selected_event
    assert(callgraph.callgraphs[event], "Invalid event!")

    local lines = {}
    local total_count = 0

    for linenr, node_info in pairs(callgraph.callgraphs[event].node_info[file]) do
        if linenr >= line_begin and linenr <= line_end then
            table.insert(lines, {file, linenr})
            total_count = total_count + node_info.count
        end
    end

    local in_counts = callgraph.merge_in_counts(event, lines)
    local nodes = {}

    for in_file, file_tbl in pairs(in_counts) do
        for in_line, count in pairs(file_tbl) do
            table.insert(nodes, {in_file, in_line, count})
        end
    end

    opts = opts or {}

    pickers.new(opts, {
        prompt_title = "",
        finder = hottest_table(nodes, total_count),
        sorter = tconf.file_sorter(opts),
        previewer = tconf.grep_previewer(opts)
    }):find()
end

return M
