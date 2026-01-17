--- Telescope pickers to find hottest lines in the code base.
-- TODO: Allow using different events than the current one.

-- All the telescope stuff...
local telescope = require("telescope")
local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local finders = require("telescope.finders")
local tconf = require("telescope.config").values
local state = require("telescope.actions.state")

local perfanno = require("perfanno")
local callgraph = require("perfanno.callgraph")
local annotate = require("perfanno.annotate")
local config = require("perfanno.config")
local find_hottest = require("perfanno.find_hottest")

--- Creates a telescope finder based on a table of lines / symbols.
-- @param entries Table to be used.
-- @param total_count Total count of events for relative annotations.
-- @return Returns the telescope finder.
local function finder_from_table(entries, total_count)
    local opts = { results = entries }

    opts.entry_maker = function(entry)
        if not config.should_display(entry.count, total_count) then
            return nil
        end

        local display = find_hottest.format_entry(entry, total_count)

        return {
            lnum = entry.linenr or 1,
            lnum_end = entry.linenr_end or 1,
            path = entry.file or "",
            display = display,
            ordinal = display, -- TODO: better ordinal?
            row = entry.linenr or 1,
            col = 0,
        }
    end

    return finders.new_table(opts)
end

local previewer_ns = vim.api.nvim_create_namespace("perfanno.telescope_previewer")

--- Provides a telescope previeer that calls "annotate_fn" on each buffer to annotate it.
-- @param annotate_fn Function that takes a buffer number and a file, gets called whenever a new
--        file is loaded into that buffer.
-- @return Returns the telescope previewer.
local function annotated_previewer(annotate_fn)
    return previewers.new_buffer_previewer {
        define_preview = function(self, entry, _)
            if entry.path == "" then
                return
            end

            local update_cursor = function(bufnr)
                vim.api.nvim_buf_clear_namespace(bufnr, previewer_ns, 0, -1)
                vim.api.nvim_buf_set_extmark(bufnr, previewer_ns, entry.lnum - 1, 0, {
                    end_row = entry.lnum - 1,
                    hl_group = "TelescopePreviewLine",
                    hl_eol = true,
                })
                vim.api.nvim_win_set_cursor(self.state.winid, { entry.lnum, 0 })
                vim.api.nvim_buf_call(bufnr, function()
                    vim.cmd("norm! zz")
                end)
            end

            -- This is the recommended caching mechanism for telescope. This way we don't need to
            -- reannotate the same buffer while we are switching between lines.
            if self.state.bufname ~= entry.path then
                local opts = {
                    callback = function(bufnr)
                        if config.values.telescope.annotate then
                            annotate_fn(bufnr, entry.path)
                        end

                        pcall(update_cursor, bufnr)
                    end,
                }

                tconf.buffer_previewer_maker(entry.path, self.state.bufnr, opts)
            else
                pcall(update_cursor, self.state.bufnr)
            end
        end,

        get_buffer_by_name = function(_, entry)
            return entry.path
        end,

        title = "File Preview",
    }
end

local pa_actions = {}

--- Telescope action that changes the current finder to the hottest callers of the selected entry.
-- @param bufnr Buffer number of the prompt.
function pa_actions.hottest_callers(bufnr)
    local selection = state.get_selected_entry()

    if selection.path == "" then
        vim.notify("No path associated to this entry!", vim.log.levels.ERROR)
        return
    end

    local new_entries, new_count = find_hottest.hottest_callers_table(
        config.selected_event,
        selection.path,
        selection.lnum,
        selection.lnum_end
    )
    local finder = finder_from_table(new_entries, new_count)
    local picker = state.get_current_picker(bufnr)

    picker:refresh(finder, { reset_prompt = true })
end

--- Telescope action that changes the current finder to the hottest callees of the selected entry.
-- @param bufnr Buffer number of the prompt.
function pa_actions.hottest_callees(bufnr)
    local selection = state.get_selected_entry()

    if selection.path == "" then
        vim.notify("No path associated to this entry!", vim.log.levels.ERROR)
        return
    end

    local new_entries, new_count = find_hottest.hottest_callees_table(
        config.selected_event,
        selection.path,
        selection.lnum,
        selection.lnum_end
    )
    local finder = finder_from_table(new_entries, new_count)
    local picker = state.get_current_picker(bufnr)

    picker:refresh(finder, { reset_prompt = true })
end

local popts = {
    mappings = {
        ["i"] = {
            ["<C-l>"] = pa_actions.hottest_callees,
            ["<C-h>"] = pa_actions.hottest_callers,
        },

        ["n"] = {
            ["gu"] = pa_actions.hottest_callers,
            ["gd"] = pa_actions.hottest_callees,
        },
    },
}

--- Attaches this plugins' mappings to the finders.
-- @param _ Buffer number of the prompt (we don't need this).
-- @param map Function that telescope passes for us to set mappings.
-- @return Always true to signal that we don't want to remove the default mappings.
function popts.attach_mappings(_, map)
    for mode, tbl in pairs(popts.mappings) do
        for key, fun in pairs(tbl) do
            map(mode, key, fun)
        end
    end

    return true
end

--- Annotates a given buffer assuming it displays the given file.
-- @param bufnr Buffer number of buffer to annotate.
-- @param file File that should be used to look up annotations.
local function annotate_file(bufnr, file)
    local cg = callgraph.callgraphs[config.selected_event]

    if not cg.node_info[file] then
        return
    end

    for linenr, node_info in pairs(cg.node_info[file]) do
        annotate.add_annotation(bufnr, linenr, node_info.count, cg.total_count, cg.max_count)
    end
end

--- Opens telescope finder to find hottest lines in the project.
-- @param opts Telescope options to override defaults from this plugin.
local function find_hottest_lines(opts)
    opts = opts or {}

    perfanno.with_event(function()
        local entries, total_count = find_hottest.hottest_lines_table(config.selected_event)

        pickers
            .new(vim.tbl_deep_extend("force", popts, opts), {
                prompt_title = "",
                finder = finder_from_table(entries, total_count),
                sorter = tconf.file_sorter {},
                previewer = annotated_previewer(annotate_file),
            })
            :find()
    end)
end

--- Opens telescope finder to find hottest symbols (functions) in the project.
-- @param opts Telescope options to override defaults from this plugin.
local function find_hottest_symbols(opts)
    opts = opts or {}

    perfanno.with_event(function()
        local entries, total_count = find_hottest.hottest_symbols_table(config.selected_event)

        pickers
            .new(vim.tbl_deep_extend("force", popts, opts), {
                prompt_title = "",
                finder = finder_from_table(entries, total_count),
                sorter = tconf.file_sorter {},
                previewer = annotated_previewer(annotate_file),
            })
            :find()
    end)
end

--- Opens telescope finder to find the hottest callers of the function containing the cursor.
-- @param opts Telescope options to override defaults from this plugin.
local function find_hottest_callers_function(opts)
    opts = opts or {}

    perfanno.with_event(function()
        local entries, total_count =
            find_hottest.hottest_callers_function_table(config.selected_event)
        if not entries then
            return
        end

        pickers
            .new(vim.tbl_deep_extend("force", popts, opts), {
                prompt_title = "",
                finder = finder_from_table(entries, total_count),
                sorter = tconf.file_sorter {},
                previewer = annotated_previewer(annotate_file),
            })
            :find()
    end)
end

--- Opens telescope finder to find the hottest callers of current visual selection.
-- @param opts Telescope options to override defaults from this plugin.
local function find_hottest_callers_selection(opts)
    opts = opts or {}

    perfanno.with_event(function()
        local entries, total_count =
            find_hottest.hottest_callers_selection_table(config.selected_event)
        if not entries then
            return
        end

        pickers
            .new(vim.tbl_deep_extend("force", popts, opts), {
                prompt_title = "",
                finder = finder_from_table(entries, total_count),
                sorter = tconf.file_sorter {},
                previewer = annotated_previewer(annotate_file),
            })
            :find()
    end)
end

--- Sets up plugin by overriding options with user provided ones.
local function setup(opts)
    popts.mappings = vim.tbl_deep_extend("force", popts.mappings, tconf.mappings)
    popts = vim.tbl_deep_extend("force", popts, opts)
end

return telescope.register_extension {
    setup = setup,

    exports = {
        -- Finders
        find_hottest_lines = find_hottest_lines,
        find_hottest_symbols = find_hottest_symbols,
        find_hottest_callers_function = find_hottest_callers_function,
        find_hottest_callers_selection = find_hottest_callers_selection,

        -- Actions
        actions = pa_actions,
    },
}
