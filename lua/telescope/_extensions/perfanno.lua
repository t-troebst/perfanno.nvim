--- Telescope pickers to find hottest lines in the code base.

-- All the telescope stuff...
local telescope = require("telescope")
local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local finders = require("telescope.finders")
local tconf = require("telescope.config").values

local perfanno = require("perfanno")
local callgraph = require("perfanno.callgraph")
local annotate = require("perfanno.annotate")
local config = require("perfanno.config")
local find_hottest = require("perfanno.find_hottest")

local function finder_from_table(entries)
    local cg = callgraph.callgraphs[config.selected_event]
    local opts = {results = entries}

    opts.entry_maker = function(entry)
        if not config.should_display(entry.count, cg.total_count) then
            return nil
        end

        local display = find_hottest.format_entry(entry, cg.total_count)

        return {
            lnum = entry.linenr or 1,
            path = entry.file or "",
            display = display,
            ordinal = display,  -- TODO: better ordinal?
            row = entry.linenr or 1,
            col = 0
        }
    end

    return finders.new_table(opts)
end

local function annotated_previewer(annotate_fn)
    return previewers.new_buffer_previewer {
        define_preview = function(self, entry, _)
            if entry.path == "" then
                return
            end

            if self.state.bufname ~= entry.path then
                local opts = {
                    callback = function(bufnr)
                        if config.values.telescope.annotate then
                            annotate_fn(bufnr, entry.path)
                        end

                        vim.api.nvim_win_set_cursor(self.state.winid, {entry.lnum, 0})
                    end
                }

                tconf.buffer_previewer_maker(entry.path, self.state.bufnr, opts)
            else
                vim.api.nvim_win_set_cursor(self.state.winid, {entry.lnum, 0})
            end
        end,

        get_buffer_by_name = function(_, entry)
            return entry.path
        end,

        title = "File Preview",
    }
end

local function annotate_file(bufnr, file)
    local cg = callgraph.callgraphs[config.selected_event]

    if not cg.node_info[file] then
        return
    end

    for linenr, node_info in pairs(cg.node_info[file]) do
        annotate.add_annotation(bufnr, linenr, node_info.count, cg.total_count, cg.max_count)
    end
end

local function find_hottest_lines()
    perfanno.with_event(function()
        local entries = find_hottest.hottest_lines_table(config.selected_event)

        pickers.new({}, {
            prompt_title = "",
            finder = finder_from_table(entries),
            sorter = tconf.file_sorter{},
            previewer = annotated_previewer(annotate_file)
        }):find()
    end)
end

local function find_hottest_symbols()
    perfanno.with_event(function()
        local entries = find_hottest.hottest_symbols_table(config.selected_event)

        pickers.new({}, {
            prompt_title = "",
            finder = finder_from_table(entries),
            sorter = tconf.file_sorter{},
            previewer = annotated_previewer(annotate_file)
        }):find()
    end)
end

local function find_hottest_callers_function()
    perfanno.with_event(function()
        local entries = find_hottest.hottest_callers_function_table(config.selected_event)

        if not entries then
            return
        end

        pickers.new({}, {
            prompt_title = "",
            finder = finder_from_table(entries),
            sorter = tconf.file_sorter{},
            previewer = annotated_previewer(annotate_file)
        }):find()
    end)
end

local function find_hottest_callers_selection()
    perfanno.with_event(function()
        local entries = find_hottest.hottest_callers_selection_table(config.selected_event)

        if not entries then
            return
        end

        pickers.new({}, {
            prompt_title = "",
            finder = finder_from_table(entries),
            sorter = tconf.file_sorter{},
            previewer = annotated_previewer(annotate_file)
        }):find()
    end)
end

return telescope.register_extension {
    exports = {
        find_hottest_lines = find_hottest_lines,
        find_hottest_symbols = find_hottest_symbols,
        find_hottest_callers_function = find_hottest_callers_function,
        find_hottest_callers_selection = find_hottest_callers_selection,
    }
}
