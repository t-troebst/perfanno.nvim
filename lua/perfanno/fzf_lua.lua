--- fzf-lua integration for finding hottest lines in the codebase.

local fzf_lua = require("fzf-lua")
local builtin = require("fzf-lua.previewer.builtin")

local perfanno = require("perfanno")
local callgraph = require("perfanno.callgraph")
local annotate = require("perfanno.annotate")
local config = require("perfanno.config")
local find_hottest = require("perfanno.find_hottest")

local M = {}

--- Annotates a given buffer assuming it displays the given file.
-- @param bufnr Buffer number of buffer to annotate.
-- @param file File that should be used to look up annotations.
local function annotate_file(bufnr, file)
    local cg = callgraph.callgraphs[config.selected_event]

    if not cg or not cg.node_info[file] then
        return
    end

    -- Get the buffer's line count to avoid out-of-range errors
    local line_count = vim.api.nvim_buf_line_count(bufnr)

    for linenr, node_info in pairs(cg.node_info[file]) do
        -- Only annotate if the line exists in the buffer
        if linenr <= line_count then
            annotate.add_annotation(bufnr, linenr, node_info.count, cg.total_count, cg.max_count)
        end
    end
end

--- Custom previewer that annotates files with profiling data.
local PerfannoPreviewer = builtin.buffer_or_file:extend()

function PerfannoPreviewer:new(o, opts, fzf_win)
    PerfannoPreviewer.super.new(self, o, opts, fzf_win)
    setmetatable(self, PerfannoPreviewer)
    return self
end

function PerfannoPreviewer:parse_entry(entry_str)
    -- If already a table, return it (parent class may call this again)
    if type(entry_str) == "table" then
        return entry_str
    end

    -- Entry format: "15.23% func at file.lua:42" or "15.23% file.lua:42"
    -- We need to extract the file path and line number

    -- Try to match "at path:line" pattern first (for symbols)
    local path, line = entry_str:match(" at ([^:]+):(%d+)")
    if path and line then
        -- Expand the path back to full path
        path = vim.fn.fnamemodify(path, ":p")
        return {
            path = path,
            line = tonumber(line),
            col = 1,
        }
    end

    -- Try to match just "path:line" pattern (for lines without symbol)
    path, line = entry_str:match("%%? ([^:]+):(%d+)")
    if path and line then
        path = vim.fn.fnamemodify(path, ":p")
        return {
            path = path,
            line = tonumber(line),
            col = 1,
        }
    end

    return nil
end

function PerfannoPreviewer:populate_preview_buf(entry_str)
    local entry = self:parse_entry(entry_str)
    if not entry or not entry.path or entry.path == "" then
        self:clear_preview_buf("No file to preview")
        return
    end

    -- Check if file is readable
    if vim.fn.filereadable(entry.path) == 0 then
        self:clear_preview_buf("File not readable: " .. entry.path)
        return
    end

    -- Call parent's populate_preview_buf with the entry table
    -- This will handle the file loading
    PerfannoPreviewer.super.populate_preview_buf(self, entry)

    -- Annotate the buffer after it's been populated
    if config.values.fzf_lua.annotate and self.preview_bufnr then
        vim.schedule(function()
            local bufnr = self.preview_bufnr
            if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
                -- Clear any existing annotations first
                annotate.clear_buffer(bufnr)

                -- Add new annotations
                local file = vim.loop.fs_realpath(entry.path) or entry.path
                annotate_file(bufnr, file)

                -- Set cursor position
                if
                    entry.line
                    and self.win
                    and vim.api.nvim_win_is_valid(self.win.preview_winid)
                then
                    pcall(vim.api.nvim_win_set_cursor, self.win.preview_winid, { entry.line, 0 })
                end
            end
        end)
    end
end

-- Global mapping from display string to original entry data
local entry_map = {}

--- Builds fzf entries from hottest entries table.
-- @param entries Table of entries from find_hottest module.
-- @param total_count Total count for formatting.
-- @return Table of formatted string entries.
local function build_fzf_entries(entries, total_count)
    local result = {}
    local new_entry_map = {} -- Clear previous mappings

    for _, entry in ipairs(entries) do
        if config.should_display(entry.count, total_count) then
            local display = find_hottest.format_entry(entry, total_count)
            table.insert(result, display)
            -- Store the original entry data for navigation
            new_entry_map[display] = entry
        end
    end

    if #result ~= 0 then
        entry_map = new_entry_map
    end

    return result
end

--- Parses a formatted entry back to path and line info.
-- @param entry_str Formatted entry string.
-- @return path, line, line_end or nil if parsing fails.
local function parse_entry(entry_str)
    -- Try to match "at path:line" pattern first (for symbols)
    local path, line, line_end = entry_str:match(" at ([^:]+):(%d+)%-(%d+)$")
    if path and line then
        return vim.fn.fnamemodify(path, ":p"), tonumber(line), tonumber(line_end)
    end

    path, line = entry_str:match(" at ([^:]+):(%d+)$")
    if path and line then
        return vim.fn.fnamemodify(path, ":p"), tonumber(line), tonumber(line)
    end

    -- Try to match just "path:line" pattern (for lines without symbol)
    path, line, line_end = entry_str:match("%%? ([^:]+):(%d+)%-(%d+)$")
    if path and line then
        return vim.fn.fnamemodify(path, ":p"), tonumber(line), tonumber(line_end)
    end

    path, line = entry_str:match("%%? ([^:]+):(%d+)$")
    if path and line then
        return vim.fn.fnamemodify(path, ":p"), tonumber(line), tonumber(line)
    end

    return nil
end

--- Default action: open file at location.
-- @param selected Table of selected entries.
local function action_file_edit(selected)
    if not selected or #selected == 0 then
        return
    end

    local entry_str = selected[1]
    local path, line = parse_entry(entry_str)

    if path and vim.fn.filereadable(path) == 1 then
        if line then
            vim.cmd(":edit +" .. line .. " " .. vim.fn.fnameescape(path))
        else
            vim.cmd(":edit " .. vim.fn.fnameescape(path))
        end
    end
end

--- Stores state for resuming picker with new entries.
local picker_state = {
    opts = nil,
    prompt_title = nil,
    entries = nil,
    history = {}, -- Stack of previous views for navigation
}

--- Reloads the picker with hottest callers of the selected entry.
-- @param selected Table of selected entries.
-- @param opts fzf-lua options.
local function action_hottest_callers(selected, opts)
    if not selected or #selected == 0 then
        return
    end

    local entry_str = selected[1]
    -- Get the original entry from the map
    local entry = entry_map[entry_str]

    if not entry then
        vim.notify("Cannot navigate callers: entry not found", vim.log.levels.WARN)
        M._run_picker(picker_state.entries, picker_state.opts or {}, picker_state.prompt_title)
        return
    end

    local new_entries, new_count

    -- Check if this is a symbol without file location
    if not entry.file or entry.file == "" then
        if entry.symbol then
            -- Navigate callers of the symbol
            new_entries, new_count =
                find_hottest.hottest_callers_symbol_table(config.selected_event, entry.symbol)
        else
            vim.notify(
                "Cannot navigate callers: no symbol or file information",
                vim.log.levels.WARN
            )
            M._run_picker(picker_state.entries, picker_state.opts or {}, picker_state.prompt_title)
            return
        end
    else
        -- Navigate callers of the file location
        local path = vim.loop.fs_realpath(entry.file) or entry.file
        local line = entry.linenr or 1
        local line_end = entry.linenr_end or line

        new_entries, new_count =
            find_hottest.hottest_callers_table(config.selected_event, path, line, line_end)
    end

    if not new_entries then
        -- Error message already shown by the callers function
        M._run_picker(picker_state.entries, picker_state.opts or {}, picker_state.prompt_title)
        return
    end

    local fzf_entries = build_fzf_entries(new_entries, new_count)

    if #fzf_entries == 0 then
        vim.notify("No callers found for this location", vim.log.levels.INFO)
        M._run_picker(picker_state.entries, picker_state.opts or {}, picker_state.prompt_title)
        return
    end

    -- Save current state to history before navigating
    table.insert(picker_state.history, {
        entries = picker_state.entries,
        prompt_title = picker_state.prompt_title,
    })

    -- Reopen picker with new entries
    M._run_picker(fzf_entries, picker_state.opts or {}, "Hottest callers")
end

--- Reloads the picker with hottest callees of the selected entry.
-- @param selected Table of selected entries.
-- @param opts fzf-lua options.
local function action_hottest_callees(selected, opts)
    if not selected or #selected == 0 then
        return
    end

    local entry_str = selected[1]
    -- Get the original entry from the map
    local entry = entry_map[entry_str]

    if not entry then
        vim.notify("Cannot navigate callees: entry not found", vim.log.levels.WARN)
        M._run_picker(picker_state.entries, picker_state.opts or {}, picker_state.prompt_title)
        return
    end

    local new_entries, new_count

    -- Check if this is a symbol without file location
    if not entry.file or entry.file == "" then
        if entry.symbol then
            -- Navigate callees of the symbol
            new_entries, new_count =
                find_hottest.hottest_callees_symbol_table(config.selected_event, entry.symbol)
        else
            vim.notify(
                "Cannot navigate callees: no symbol or file information",
                vim.log.levels.WARN
            )
            M._run_picker(picker_state.entries, picker_state.opts or {}, picker_state.prompt_title)
            return
        end
    else
        -- Navigate callees of the file location
        local path = vim.loop.fs_realpath(entry.file) or entry.file
        local line = entry.linenr or 1
        local line_end = entry.linenr_end or line

        new_entries, new_count =
            find_hottest.hottest_callees_table(config.selected_event, path, line, line_end)
    end

    if not new_entries then
        -- Error message already shown by the callees function
        M._run_picker(picker_state.entries, picker_state.opts or {}, picker_state.prompt_title)
        return
    end

    local fzf_entries = build_fzf_entries(new_entries, new_count)

    if #fzf_entries == 0 then
        vim.notify("No callees found for this location", vim.log.levels.INFO)
        M._run_picker(picker_state.entries, picker_state.opts or {}, picker_state.prompt_title)
        return
    end

    -- Save current state to history before navigating
    table.insert(picker_state.history, {
        entries = picker_state.entries,
        prompt_title = picker_state.prompt_title,
    })

    -- Reopen picker with new entries
    M._run_picker(fzf_entries, picker_state.opts or {}, "Hottest callees")
end

--- Internal function to run the fzf-lua picker.
-- @param entries Table of formatted string entries.
-- @param opts User options to override defaults.
-- @param prompt_title Title for the picker.
function M._run_picker(entries, opts, prompt_title)
    opts = opts or {}

    -- Store state for caller/callee navigation
    picker_state.opts = opts
    picker_state.prompt_title = prompt_title
    picker_state.entries = entries

    local picker_opts = vim.tbl_deep_extend("force", {
        prompt = prompt_title .. "> ",
        previewer = PerfannoPreviewer,
        actions = {
            ["default"] = action_file_edit,
            ["ctrl-h"] = action_hottest_callers,
            ["ctrl-l"] = action_hottest_callees,
        },
        fzf_opts = {
            ["--no-sort"] = "", -- Keep entries sorted by hotness
        },
    }, opts)

    fzf_lua.fzf_exec(entries, picker_opts)
end

--- Opens fzf-lua picker to find hottest lines in the project.
-- @param opts fzf-lua options to override defaults.
function M.find_hottest_lines(opts)
    opts = opts or {}

    perfanno.with_event(function()
        local entries, total_count = find_hottest.hottest_lines_table(config.selected_event)
        local fzf_entries = build_fzf_entries(entries, total_count)
        M._run_picker(fzf_entries, opts, "Hottest lines")
    end)
end

--- Opens fzf-lua picker to find hottest symbols (functions) in the project.
-- @param opts fzf-lua options to override defaults.
function M.find_hottest_symbols(opts)
    opts = opts or {}

    perfanno.with_event(function()
        local entries, total_count = find_hottest.hottest_symbols_table(config.selected_event)
        local fzf_entries = build_fzf_entries(entries, total_count)
        M._run_picker(fzf_entries, opts, "Hottest symbols")
    end)
end

--- Opens fzf-lua picker to find the hottest callers of the function containing the cursor.
-- @param opts fzf-lua options to override defaults.
function M.find_hottest_callers_function(opts)
    opts = opts or {}

    perfanno.with_event(function()
        local entries, total_count =
            find_hottest.hottest_callers_function_table(config.selected_event)
        if not entries then
            return
        end

        local fzf_entries = build_fzf_entries(entries, total_count)
        M._run_picker(fzf_entries, opts, "Hottest callers")
    end)
end

--- Opens fzf-lua picker to find the hottest callers of current visual selection.
-- @param opts fzf-lua options to override defaults.
function M.find_hottest_callers_selection(opts)
    opts = opts or {}

    perfanno.with_event(function()
        local entries, total_count =
            find_hottest.hottest_callers_selection_table(config.selected_event)
        if not entries then
            return
        end

        local fzf_entries = build_fzf_entries(entries, total_count)
        M._run_picker(fzf_entries, opts, "Hottest callers")
    end)
end

-- Export actions for user customization
M.actions = {
    file_edit = action_file_edit,
    hottest_callers = action_hottest_callers,
    hottest_callees = action_hottest_callees,
}

return M
