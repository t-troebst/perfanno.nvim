--- Performs source code annotation according to the loaded callgraph.

local callgraph = require("perfanno.callgraph")
local config = require("perfanno.config")
local util = require("perfanno.util")
local treesitter = require("perfanno.treesitter")

local M = {}

local namespace = vim.api.nvim_create_namespace("perfanno.annotations")

--- Returns file path in canonical format for the given buffer.
-- @param bnr Buffer number of file.
-- @return File path in canonical format.
local function buffer_file(bnr)
    local file = vim.fn.expand("#" .. bnr, ":p")
    return vim.loop.fs_realpath(file) or file
end

--- Adds a single annotation (highlight + virtual text) at a given line in a given buffer.
-- @param bnr Buffer number to annotate.
-- @param linenr Line number to annotate.
-- @param count Event count that will be used for annotation.
-- @param total_count Total count of that event (for percentages).
-- @param max_count Maximum count of that event (for line highlight).
function M.add_annotation(bnr, linenr, count, total_count, max_count)
    local fmt = config.format(count, total_count)

    if not fmt then
        return
    end

    if config.values.line_highlights then
        local i = 1 + util.round((#config.values.line_highlights - 1) * count / max_count)

        vim.api.nvim_buf_add_highlight(bnr, namespace, config.values.line_highlights[i],
            linenr - 1, 0, -1)
    end

    if config.values.vt_highlight then
        local vopts = {
            virt_text = {{fmt, config.values.vt_highlight}},
            virt_text_pos = "eol"
        }

        vim.api.nvim_buf_set_extmark(bnr, namespace, linenr - 1, 0, vopts)
    end
end

--- Annotates buffer with given buffer number for given event.
-- @param bnr Buffer number to annotate, current if nil.
-- @param event Event to annotate, current if nil.
function M.annotate_buffer(bnr, event)
    event = event or config.selected_event
    callgraph.check_event(event)

    bnr = bnr or vim.api.nvim_get_current_buf()
    local file = buffer_file(bnr)

    if not callgraph.callgraphs[event].node_info[file] then
        return false
    end

    M.clear_buffer(bnr)

    local total_count = callgraph.callgraphs[event].total_count
    local max_count = callgraph.callgraphs[event].max_count

    for linenr, info in pairs(callgraph.callgraphs[event].node_info[file]) do
        M.add_annotation(bnr, linenr, info.count, total_count, max_count)
    end
end

--- Annotates a range of lines inside of a given buffer for a given event.
-- @param bnr Buffer number to annotate, current if nil.
-- @param line_begin First line to annotate (inclusive).
-- @param line_end Last line to annotate (exclusive).
-- @param event Event to annotate for, current if nil.
function M.annotate_range(bnr, line_begin, line_end, event)
    event = event or config.selected_event
    callgraph.check_event(event)

    bnr = bnr or vim.api.nvim_get_current_buf()
    local file = buffer_file(bnr)

    if not callgraph.callgraphs[event].node_info[file] then
        return false
    end

    M.clear_buffer(bnr)

    local total_count = 0
    local max_count = 0

    for linenr, info in pairs(callgraph.callgraphs[event].node_info[file]) do
        if linenr >= line_begin and linenr <= line_end then
            total_count = total_count + info.count
            max_count = math.max(max_count, info.count)
        end
    end

    for linenr, info in pairs(callgraph.callgraphs[event].node_info[file]) do
        if linenr >= line_begin and linenr <= line_end then
            M.add_annotation(bnr, linenr, info.count, total_count, max_count)
        end
    end
end

--- Annotates the function that contains the cursor for given event.
-- @param event Event to annotate for, current if nil.
function M.annotate_function(event)
    local line_begin, line_end = treesitter.get_function_lines()

    if line_begin and line_end then
        M.annotate_range(nil, line_begin, line_end, event)
    end
end

--- Annotates current visual selection for given event.
-- @param event Event to annotate for, current if nil.
function M.annotate_selection(event)
    local line_begin, _, line_end, _ = util.visual_selection_range()

    if line_begin and line_end then
        M.annotate_range(nil, line_begin, line_end, event)
    end
end

--- Clears annotations in buffer with given buffer number.
-- @param bnr Buffer number to clear, current if nil.
function M.clear_buffer(bnr)
    bnr = bnr or vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(bnr, namespace, 0, -1)
end

local toggled = false

--- Annotates all buffers for information from given event.
-- @param event Event to annotate for, fall back to current event if nil.
function M.annotate(event)
    toggled = true

    for _, bnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bnr) then
            M.annotate_buffer(bnr, event)
        end
    end
end

--- Clears annotations on all buffers.
function M.clear()
    toggled = false

    for _, bnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bnr) then
            M.clear_buffer(bnr)
        end
    end
end

--- Toggles annotations on all buffers for given event.
-- @param event Event to annotate for, current if nil.
function M.toggle_annotations(event)
    if toggled then
        M.clear()
    else
        M.annotate(event)
    end
end

--- Returns whether annotations are currently toggled on or off.
-- @return true if annotations are toggled on.
function M.is_toggled()
    return toggled
end

--- Returns whether we *should* be annotating right now.
-- @return true if callgraph is loaded for current event and annotations are toggled on.
function M.should_annotate()
    if callgraph.is_loaded() and config.selected_event
        and callgraph.callgraphs[config.selected_event] and toggled then
        return true
    end

    return false
end

return M
