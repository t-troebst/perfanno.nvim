-- annotate.lua
-- Performs source code annotation according to the loaded callgraph

local callgraph = require("perfanno.callgraph")
local config = require("perfanno.config")

local M = {}

local namespaces = {}

local function add_annotation(bnr, linenr, count, total_count, max_count)
    local fmt = config.format(count, total_count)

    if not fmt then
        return
    end

    if config.line_highlights then
        local i = math.floor(#config.line_highlights * count / max_count + 0.5)

        if i > 0 then
            vim.api.nvim_buf_add_highlight(bnr, namespaces[bnr], config.line_highlights[i], linenr - 1, 0, -1)
        end
    end

    if config.vt_highlight then
        local vopts = {
            virt_text = {{fmt, config.vt_highlight}},
            virt_text_pos = "eol"
        }

        vim.api.nvim_buf_set_extmark(bnr, namespaces[bnr], linenr - 1, 0, vopts)
    end
end

local function init_namespace(bnr)
    if not namespaces[bnr] then
        namespaces[bnr] = vim.api.nvim_create_namespace("perfanno_" .. bnr)
    end
end

function M.annotate_buffer(bnr, event)
    assert(callgraph.is_loaded(), "Callgraph must be loaded for annotations!")
    event = event or config.selected_event
    assert(callgraph.callgraphs[event], "Invalid event!")

    bnr = bnr or vim.api.nvim_get_current_buf()
    init_namespace(bnr)

    local file = vim.fn.expand("#" .. bnr .. ":p")

    if not callgraph.callgraphs[event].node_info[file] then
        return false
    end

    M.clear_buffer(bnr)

    local total_count = callgraph.callgraphs[event].total_count
    local max_count = callgraph.callgraphs[event].max_count

    for linenr, info in pairs(callgraph.callgraphs[event].node_info[file]) do
        add_annotation(bnr, linenr, info.count, total_count, max_count)
    end
end

function M.annotate_range(bnr, line_begin, line_end, event)
    assert(callgraph.is_loaded(), "Callgraph must be loaded for annotations!")
    event = event or config.selected_event
    assert(callgraph.callgraphs[event], "Invalid event!")

    bnr = bnr or vim.api.nvim_get_current_buf()
    init_namespace(bnr)

    local file = vim.fn.expand("#" .. bnr .. ":p")

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
            add_annotation(bnr, linenr, info.count, total_count, max_count)
        end
    end
end

function M.clear_buffer(bnr)
    bnr = bnr or vim.api.nvim_get_current_buf()

    if namespaces[bnr] then
        vim.api.nvim_buf_clear_namespace(bnr, namespaces[bnr], 0, -1)
    end
end

local toggled = false

function M.annotate(event)
    toggled = true

    for _, bnr in ipairs(vim.api.nvim_list_bufs()) do
        M.annotate_buffer(bnr, event)
    end
end

function M.clear()
    toggled = false

    for _, bnr in ipairs(vim.api.nvim_list_bufs()) do
        M.clear_buffer(bnr)
    end
end

function M.toggle_annotations(event)
    if toggled then
        M.clear()
    else
        M.annotate(event)
    end
end

function M.is_toggled()
    return toggled
end

return M
