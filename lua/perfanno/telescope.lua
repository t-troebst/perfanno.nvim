local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values

local load_data = require("perfanno.load_data")
local show_anno = require("perfanno.show_annotations")

local function annotation_table()
    local opts = {}

    opts.results = {}

    for file, file_dir in pairs(load_data.annotations[show_anno.get_current_event()]) do
        for linenr, data in pairs(file_dir) do
            table.insert(opts.results, {file, linenr, data[1], data[2]})
        end
    end

    table.sort(opts.results, function(e1, e2)
        return e1[4] > e2[4]
    end)


    opts.entry_maker = function(entry)
        local short_path = vim.fn.fnamemodify(entry[1], ":~:.")

        return {
            lnum = entry[2],
            display = entry[3] .. " " .. short_path .. ":" .. entry[2],
            ordinal = short_path .. ":" .. entry[2],
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
