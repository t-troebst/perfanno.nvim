-- Telescope picker to find hottest lines in the code base


local telescope = require("telescope")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local tconf = require("telescope.config").values

local perfanno = require("perfanno")
local callgraph = require("perfanno.callgraph")
local config = require("perfanno.config")
local treesitter = require("perfanno.treesitter")
local util = require("perfanno.util")

local function hottest_table(nodes, total_count)
    local opts = {results = nodes}

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


local function find_hottest_lines(event)
    event = event or config.selected_event
    assert(callgraph.callgraphs[event], "Invalid event!")

    local nodes = {}

    for file, file_tbl in pairs(callgraph.callgraphs[event].node_info) do
        for linenr, node_info in pairs(file_tbl) do
            table.insert(nodes, {file, linenr, node_info.count})
        end
    end

    pickers.new({}, {
        prompt_title = "",
        finder = hottest_table(nodes, callgraph.callgraphs[event].total_count),
        sorter = tconf.file_sorter{},
        previewer = tconf.grep_previewer{}
    }):find()
end

-- TODO: there is some unnecessary code duplication here with perfanno.find_hottest
local function find_hottest_callers(file, line_begin, line_end, event)
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

    pickers.new({}, {
        prompt_title = "",
        finder = hottest_table(nodes, total_count),
        sorter = tconf.file_sorter{},
        previewer = tconf.grep_previewer{}
    }):find()
end

local function find_hottest()
    perfanno.with_event(find_hottest_lines)
end

local function find_hottest_callers_function()
    perfanno.with_event(function()
        local file = vim.fn.expand("%:p")
        local line_begin, line_end = treesitter.get_function_lines()

        if line_begin and line_end then
            find_hottest_callers(file, line_begin, line_end)
        end
    end)
end

local function find_hottest_callers_selection()
    perfanno.with_event(function()
        local file = vim.fn.expand("%:p")
        local line_begin, _, line_end, _ = util.visual_selection_range()

        if line_begin and line_end then
            find_hottest_callers(file, line_begin, line_end)
        end
    end)
end

return telescope.register_extension {
    exports = {
        find_hottest_lines = find_hottest,
        find_hottest_callers_function = find_hottest_callers_function,
        find_hottest_callers_selection = find_hottest_callers_selection,
    }
}
