--- fzf-lua integration for finding hottest lines in the codebase.

local fzf_lua = require("fzf-lua")
local builtin = require("fzf-lua.previewer.builtin")

local perfanno = require("perfanno")
local annotate = require("perfanno.annotate")
local config = require("perfanno.config")
local find_hottest = require("perfanno.find_hottest")

local M = {}

-- Global mapping from display string to original entry data
local entry_map = {}

-- Current entries and total count for the picker
local current_entries = nil
local current_total_count = nil

--- Custom previewer that annotates files with profiling data.
local PerfannoPreviewer = builtin.buffer_or_file:extend()

function PerfannoPreviewer:new(o, opts, fzf_win)
    PerfannoPreviewer.super.new(self, o, opts, fzf_win)
    setmetatable(self, PerfannoPreviewer)
    return self
end

function PerfannoPreviewer:parse_entry(entry_str)
    if type(entry_str) == "table" then
        return entry_str
    end

    local entry = entry_map[entry_str]
    if not entry or not entry.file then
        return {}
    end

    return {
        path = entry.file,
        line = entry.linenr,
        col = 1,
    }
end

function PerfannoPreviewer:preview_buf_post(entry)
    PerfannoPreviewer.super.preview_buf_post(self, entry)

    if config.values.fzf_lua.annotate and self.preview_bufnr then
        if vim.api.nvim_buf_is_valid(self.preview_bufnr) then
            annotate.annotate_buffer_for_file(self.preview_bufnr, entry.path)
        end
    end
end

--- Contents function for fzf-lua that generates entries from current state.
-- @param cb Callback function to send entries to fzf.
local function contents_fn(cb)
    if not current_entries then
        cb(nil)
        return
    end

    entry_map = {}

    for _, entry in ipairs(current_entries) do
        if config.should_display(entry.count, current_total_count) then
            local display = find_hottest.format_entry(entry, current_total_count)
            entry_map[display] = entry
            cb(display)
        end
    end

    cb(nil)
end

--- Default action: open file at location.
local function action_file_edit(selected)
    if not selected or #selected == 0 then
        return
    end

    local entry = entry_map[selected[1]]
    if not entry.file then
        return
    end

    vim.cmd(":edit +" .. entry.linenr .. " " .. vim.fn.fnameescape(entry.file))
end

--- Creates a navigation action for callers or callees.
-- @param direction "callers" or "callees"
-- @return Action function for fzf-lua.
local function make_navigation_action(direction)
    local symbol_fn = direction == "callers" and find_hottest.hottest_callers_symbol_table
        or find_hottest.hottest_callees_symbol_table
    local location_fn = direction == "callers" and find_hottest.hottest_callers_table
        or find_hottest.hottest_callees_table

    return function(selected)
        if not selected or #selected == 0 then
            return
        end

        local entry = entry_map[selected[1]]
        local new_entries, new_total_count
        if entry.file then
            new_entries, new_total_count =
                location_fn(config.selected_event, entry.file, entry.linenr, entry.linenr_end)
        else
            new_entries, new_total_count = symbol_fn(config.selected_event, entry.symbol)
        end

        if not new_entries or #new_entries == 0 then
            vim.notify("No " .. direction .. " found for this location", vim.log.levels.INFO)
            return
        end

        current_entries = new_entries
        current_total_count = new_total_count
    end
end

local action_hottest_callers = make_navigation_action("callers")
local action_hottest_callees = make_navigation_action("callees")

--- Internal function to run the fzf-lua picker.
-- @param entries Table of entries from find_hottest.
-- @param total_count Total count for percentage calculation.
-- @param opts User options to override defaults.
-- @param prompt_title Title for the picker.
function M._run_picker(entries, total_count, opts, prompt_title)
    opts = opts or {}
    current_entries = entries
    current_total_count = total_count

    local picker_opts = vim.tbl_deep_extend("force", {
        prompt = prompt_title .. "> ",
        previewer = PerfannoPreviewer,
        actions = {
            ["default"] = action_file_edit,
            ["ctrl-h"] = { fn = action_hottest_callers, reload = true },
            ["ctrl-l"] = { fn = action_hottest_callees, reload = true },
        },
        fzf_opts = {
            ["--no-sort"] = "",
        },
    }, opts)

    fzf_lua.fzf_exec(contents_fn, picker_opts)
end

--- Helper to create a picker function.
-- @param find_fn Function from find_hottest module to get entries.
-- @param title Title for the picker.
-- @return Picker function that takes opts.
local function make_picker(find_fn, title)
    return function(opts)
        opts = opts or {}
        perfanno.with_event(function()
            local entries, total_count = find_fn(config.selected_event)
            if not entries then
                return
            end
            M._run_picker(entries, total_count, opts, title)
        end)
    end
end

M.find_hottest_lines = make_picker(find_hottest.hottest_lines_table, "Hottest lines")
M.find_hottest_symbols = make_picker(find_hottest.hottest_symbols_table, "Hottest symbols")
M.find_hottest_callers_function =
    make_picker(find_hottest.hottest_callers_function_table, "Hottest callers")
M.find_hottest_callers_selection =
    make_picker(find_hottest.hottest_callers_selection_table, "Hottest callers")

-- Export actions for user customization
M.actions = {
    file_edit = action_file_edit,
    hottest_callers = action_hottest_callers,
    hottest_callees = action_hottest_callees,
}

return M
