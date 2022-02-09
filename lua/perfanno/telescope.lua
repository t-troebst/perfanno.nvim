local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values

local callgraph = require("perfanno.callgraph")
local annotate = require("perfanno.annotate")

local function annotation_table(event, anno_opts)
    local opts = {}

    opts.results = {}

    for file, file_tbl in pairs(callgraph.callgraphs[event].node_info) do
        for linenr, node_info in pairs(file_tbl) do
            table.insert(opts.results, {file, linenr, node_info.count})
        end
    end

    table.sort(opts.results, function(e1, e2)
        return e1[3] > e2[3]
    end)


    opts.entry_maker = function(entry)
        local fmt = annotate.format_annotation(entry[3], callgraph.callgraphs[event].total_count, anno_opts)

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

local M = {}

function M.find_hottest(event, anno_opts, telescope_opts)
    assert(callgraph.is_loaded(), "Callgraph is not loaded!")
    assert(callgraph.callgraphs[event], "Invalid event!")

    telescope_opts = telescope_opts or {}

    pickers.new(telescope_opts, {
        prompt_title = "",
        finder = annotation_table(event, anno_opts),
        sorter = conf.file_sorter(telescope_opts),
        previewer = conf.grep_previewer(telescope_opts)
    }):find()
end

return M
