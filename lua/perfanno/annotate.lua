-- annotate.lua
-- Performs source code annotation according to the loaded callgraph

local callgraph = require("perfanno.callgraph")

local M = {}

local namespaces = {}

function M.format_annotation(count, total, opts)
    if opts.numbers == "percent" then
        if count / total * 100 >= opts.minimum then
            return string.format(opts.format, count / total * 100)
        end
    else
        if count >= opts.minimum then
            return string.format(opts.format, count)
        end
    end
end

local function add_annotation(bnr, linenr, count, total_count, max_count, opts)
    local fmt = M.format_annotation(count, total_count, opts)

    if not fmt then
        return
    end

    if opts.highlights then
        local i = math.floor(#opts.highlights * count / max_count + 0.5)

        if i > 0 then
            vim.api.nvim_buf_add_highlight(bnr, namespaces[bnr], opts.highlights[i], linenr - 1, 0, -1)
        end
    end

    if opts.virtual_text then
        local vopts = {
            virt_text = {{fmt, opts.virtual_text.highlight}},
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

function M.annotate_buffer(bnr, event, opts)
    assert(callgraph.is_loaded(), "Callgraph must be loaded for annotations!")
    assert(callgraph.callgraphs[event], "Invalid event!")

    init_namespace(bnr)

    local file = vim.fn.expand("#" .. bnr .. ":p")

    if not callgraph.callgraphs[event].node_info[file] then
        return false
    end

    M.clear_buffer(bnr)

    local total_count = callgraph.callgraphs[event].total_count
    local max_count = callgraph.callgraphs[event].max_count

    for linenr, info in pairs(callgraph.callgraphs[event].node_info[file]) do
        add_annotation(bnr, linenr, info.count, total_count, max_count, opts)
    end
end

function M.annotate_range(bnr, event, line_begin, line_end, opts)
    assert(callgraph.is_loaded(), "Callgraph must be loaded for annotations!")
    assert(callgraph.callgraphs[event], "Invalid event!")

    init_namespace(bnr)

    local file = vim.fn.expand("#" .. bnr .. ":p")

    if not callgraph.callgraphs[event].node_info[file] then
        return false
    end

    M.clear_buffer(bnr)

    local total_count = callgraph.callgraphs[event].total_count
    local max_count = callgraph.callgraphs[event].max_count

    if opts.relative then
        total_count = 0
        max_count = 0

        for linenr, info in pairs(callgraph.callgraphs[event].node_info[file]) do
            if linenr >= line_begin and linenr < line_end then
                total_count = total_count + info.count
                max_count = math.max(max_count, info.count)
            end
        end
    end

    for linenr, info in pairs(callgraph.callgraphs[event].node_info[file]) do
        if linenr >= line_begin and linenr < line_end then
            add_annotation(bnr, linenr, info.count, total_count, max_count, opts)
        end
    end
end

function M.clear_buffer(bnr)
    if namespaces[bnr] then
        vim.api.nvim_buf_clear_namespace(bnr, namespaces[bnr], 0, -1)
    end
end

local toggled = false

function M.annotate(event, opts)
    assert(callgraph.is_loaded(), "Callgraph must be loaded for annotations!")
    assert(callgraph.callgraphs[event], "Invalid event!")

    toggled = true

    for _, bnr in ipairs(vim.api.nvim_list_bufs()) do
        M.annotate_buffer(bnr, event, opts)
    end
end

function M.clear()
    toggled = false

    for _, bnr in ipairs(vim.api.nvim_list_bufs()) do
        M.clear_buffer(bnr)
    end
end

function M.toggle_annotations(event, opts)
    if toggled then
        M.clear()
    else
        M.annotate(event, opts)
    end
end

function M.is_toggled()
    return toggled
end

return M
