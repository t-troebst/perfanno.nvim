local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values

local load_data = require("perfanno.load_data")
local show_anno = require("perfanno.show_annotations")

local function annotation_table()
    local opts = {}

    opts.results = {}

    for file, file_dir in pairs(load_data.annotations[show_anno.get_current_event()]) do
        for linenr, pct in pairs(file_dir) do
            table.insert(opts.results, {file, linenr, pct})
        end
    end

    table.sort(opts.results, function(e1, e2)
        return e1[3] > e2[3]
    end)

    opts.entry_maker = function(entry)
        return {
            lnum = entry[2],
            display = string.format("%05.2f", entry[3]) .. "% " .. entry[1] .. ":" .. entry[2],
            ordinal = entry[1] .. ":" .. entry[2],
            path = entry[1],
            row = entry[2],
            col = 0
        }
    end

    return finders.new_table(opts)
end

local M = {}

function M.find_hottest(opts)
    if not show_anno.get_current_event() then
        print("Annotations not loaded, do :PerfAnnoAnnotate first!")
        return
    end

    opts = opts or {}

    pickers.new(opts, {
        prompt_title = "",
        finder = annotation_table(),
        sorter = conf.file_sorter(opts),
        previewer = conf.grep_previewer(opts)
    }):find()
end

return M
