-- Finds hottest lines and callers
-- This is a fallback if telescope is not installed

local callgraph = require("perfanno.callgraph")
local treesitter = require("perfanno.treesitter")
local config = require("perfanno.config")
local util = require("perfanno.util")

local M = {}

local function go_to_entry(entry)
    if entry and entry[2] ~= "symbol" then
        -- Isn't there a way to do this via the lua API??
        vim.cmd(":edit +" .. entry[3] .. " " .. vim.fn.fnameescape(entry[2]))
    end
end

local function format_entry(total)
    return function(entry)
        local fmt = config.format(entry[4], total)
        local short_path = vim.fn.fnamemodify(entry[2], ":~:.")

        if entry[2] == "symbol" then
            return fmt .. " " .. entry[3]
        end

        if entry[1] ~= "" then
            return fmt .. " " .. entry[1] .. " at " .. short_path .. ":" .. entry[3]
        else
            return fmt .. " " .. short_path .. ":" .. entry[3]
        end
    end
end

function M.find_hottest_lines(event)
    assert(callgraph.is_loaded(), "Callgraph is not loaded!")
    event = event or config.selected_event
    assert(callgraph.callgraphs[event], "Invalid event!")

    local entries = {}

    for file, file_tbl in pairs(callgraph.callgraphs[event].node_info) do
        for linenr, node_info in pairs(file_tbl) do
            if config.format(node_info.count, callgraph.callgraphs[event].total_count) then
                table.insert(entries, {"", file, linenr, node_info.count})
            end
        end
    end

    table.sort(entries, function(e1, e2)
        return e1[4] > e2[4]
    end)

    local opts = {
        prompt = "Hottest lines: ",
        format_item = format_entry(callgraph.callgraphs[event].total_count),
        kind = "file"
    }

    vim.ui.select(entries, opts, go_to_entry)
end

function M.find_hottest_symbols(event)
    assert(callgraph.is_loaded(), "Callgraph is not loaded!")
    event = event or config.selected_event
    assert(callgraph.callgraphs[event], "Invalid event!")

    local entries = {}
    local cg = callgraph.callgraphs[event]

    for file, syms in pairs(cg.symbols) do
        for sym, info in pairs(syms) do
            if config.format(info.count, cg.total_count) then
                table.insert(entries, {sym, file, info.min_line, info.count})
            end
        end
    end

    for sym, info in pairs(cg.node_info.symbol) do
        if config.format(info.count, cg.total_count) then
            table.insert(entries, {"", "symbol", sym, info.count})
        end
    end

    table.sort(entries, function(e1, e2)
        return e1[4] > e2[4]
    end)

    local opts = {
        prompt = "Hottest lines: ",
        format_item = format_entry(callgraph.callgraphs[event].total_count),
        kind = "file"
    }

    vim.ui.select(entries, opts, go_to_entry)
end

local function find_hottest_callers(event, file, line_begin, line_end)
    assert(callgraph.is_loaded(), "Callgraph is not loaded!")
    event = event or config.selected_event
    assert(callgraph.callgraphs[event], "Invalid event!")

    local lines = {}
    local total_count = 0

    for linenr, node_info in pairs(callgraph.callgraphs[event].node_info[file]) do
        if linenr >= line_begin and linenr <= line_end then
            table.insert(lines, {file, linenr})
            total_count = total_count + node_info.count
        end
    end

    local in_counts = callgraph.merge_in_counts(event, lines)
    local entries = {}

    for in_file, file_tbl in pairs(in_counts) do
        for in_line, count in pairs(file_tbl) do
            if config.format(count, total_count) then
                table.insert(entries, {"", in_file, in_line, count})
            end
        end
    end

    table.sort(entries, function(e1, e2)
        return e1[4] > e2[4]
    end)

    local opts = {
        prompt = "Hottest lines: ",
        format_item = format_entry(total_count),
        kind = "files"
    }

    vim.ui.select(entries, opts, go_to_entry)
end


function M.find_hottest_callers_function(event)
    local file = vim.fn.expand("%:p"):gsub("/+", "/")
    local line_begin, line_end = treesitter.get_function_lines()

    if line_begin and line_end then
        find_hottest_callers(event, file, line_begin, line_end)
    end
end

function M.find_hottest_callers_selection(event)
    local file = vim.fn.expand("%:p"):gsub("/+", "/")
    local line_begin, _, line_end, _ = util.visual_selection_range()

    if line_begin and line_end then
        find_hottest_callers(event, file, line_begin, line_end)
    end
end

return M
