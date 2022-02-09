-- telescope.lua
-- Telescope picker to find hottest lines in the code base
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values

local callgraph = require("perfanno.callgraph")
local annotate = require("perfanno.annotate")

local M = {}

local function hottest_table(nodes, total_count, event, anno_opts)
    local opts = {}

    opts.results = nodes

    table.sort(opts.results, function(e1, e2)
        return e1[3] > e2[3]
    end)


    opts.entry_maker = function(entry)
        local fmt = annotate.format_annotation(entry[3], total_count, anno_opts)

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


function M.find_hottest(event, anno_opts, telescope_opts)
    assert(callgraph.is_loaded(), "Callgraph is not loaded!")
    assert(callgraph.callgraphs[event], "Invalid event!")

    local nodes = {}

    for file, file_tbl in pairs(callgraph.callgraphs[event].node_info) do
        for linenr, node_info in pairs(file_tbl) do
            table.insert(nodes, {file, linenr, node_info.count})
        end
    end

    telescope_opts = telescope_opts or {}

    pickers.new(telescope_opts, {
        prompt_title = "",
        finder = hottest_table(nodes, callgraph.callgraphs[event].total_count, event, anno_opts),
        sorter = conf.file_sorter(telescope_opts),
        previewer = conf.grep_previewer(telescope_opts)
    }):find()
end

function M.find_hottest_callers(file, line_begin, line_end, event, anno_opts, telescope_opts)
    assert(callgraph.is_loaded(), "Callgraph is not loaded!")
    assert(callgraph.callgraphs[event], "Invalid event!")

    local lines = {}
    local total_count = 0

    for linenr, node_info in pairs(callgraph.callgraphs[event].node_info[file]) do
        if linenr >= line_begin and linenr < line_end then
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

    telescope_opts = telescope_opts or {}

    pickers.new(telescope_opts, {
        prompt_title = "",
        finder = hottest_table(nodes, total_count, event, anno_opts),
        sorter = conf.file_sorter(telescope_opts),
        previewer = conf.grep_previewer(telescope_opts)
    }):find()
end

return M
