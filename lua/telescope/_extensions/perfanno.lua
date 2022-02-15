-- Telescope picker to find hottest lines in the code base


local telescope = require("telescope")
local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local finders = require("telescope.finders")
local tconf = require("telescope.config").values

local perfanno = require("perfanno")
local callgraph = require("perfanno.callgraph")
local annotate = require("perfanno.annotate")
local config = require("perfanno.config")
local treesitter = require("perfanno.treesitter")
local util = require("perfanno.util")

local function hottest_table(entries, total_count)
    local opts = {results = entries}

    table.sort(opts.results, function(e1, e2)
        return e1[4] > e2[4]
    end)

    opts.entry_maker = function(entry)
        local fmt = config.format(entry[4], total_count)

        if not fmt then
            return
        end

        if entry[2] == "symbol" then
            return {
                lnum = 0,
                display = fmt .. " " .. entry[3],
                ordinal = entry[3],
                path = "",
                row = 0,
                col = 0,
            }
        end

        local short_path = vim.fn.fnamemodify(entry[2], ":~:.")
        local display

        if entry[1] and entry[1] ~= "" then
            display = fmt .. " " .. entry[1] .. " at " .. short_path .. ":" .. entry[3]
        else
            display = fmt .. " " .. short_path .. ":" .. entry[3]
        end

        return {
            lnum = entry[3],
            display = display,
            ordinal = short_path .. ":" .. entry[3],
            path = entry[2],
            row = entry[3],
            col = 0
        }
    end

    return finders.new_table(opts)
end

local function annotated_previewer(annotate_file)
    return previewers.new_buffer_previewer {
        define_preview = function(self, entry, _)
            if entry.path == "" then
                return
            end

            if self.state.bufname ~= entry.path then
                local opts = {
                    callback = function(bufnr)
                        if config.values.telescope.annotate then
                            annotate_file(bufnr, entry.path)
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

local function find_hottest_lines(event)
    event = event or config.selected_event
    assert(callgraph.callgraphs[event], "Invalid event!")

    local entries = {}
    local cg = callgraph.callgraphs[event]

    for file, file_tbl in pairs(cg.node_info) do
        for linenr, node_info in pairs(file_tbl) do
            table.insert(entries, {"", file, linenr, node_info.count})
        end
    end

    local function annotate_file(bufnr, file)
        if not cg.node_info[file] then
            return
        end

        for linenr, node_info in pairs(cg.node_info[file]) do
            annotate.add_annotation(bufnr, linenr, node_info.count, cg.total_count, cg.max_count)
        end
    end

    pickers.new({}, {
        prompt_title = "",
        finder = hottest_table(entries, callgraph.callgraphs[event].total_count),
        sorter = tconf.file_sorter{},
        previewer = annotated_previewer(annotate_file),
    }):find()
end

local function find_hottest_symbols(event)
    event = event or config.selected_event
    assert(callgraph.callgraphs[event], "Invalid event!")

    local entries = {}
    local cg = callgraph.callgraphs[event]

    for file, syms in pairs(cg.symbols) do
        for sym, info in pairs(syms) do
            table.insert(entries, {sym, file, info.min_line, info.count})
        end
    end

    for sym, info in pairs(cg.node_info.symbol) do
        table.insert(entries, {"", "symbol", sym, info.count})
    end

    local function annotate_file(bufnr, file)
        if not cg.node_info[file] then
            return
        end

        for linenr, node_info in pairs(cg.node_info[file]) do
            annotate.add_annotation(bufnr, linenr, node_info.count, cg.total_count, cg.max_count)
        end
    end

    pickers.new({}, {
        prompt_title = "",
        finder = hottest_table(entries, callgraph.callgraphs[event].total_count),
        sorter = tconf.file_sorter{},
        previewer = annotated_previewer(annotate_file),
    }):find()
end

-- TODO: there is some unnecessary code duplication here with perfanno.find_hottest
local function find_hottest_callers(file, line_begin, line_end, event)
    event = event or config.selected_event
    assert(callgraph.callgraphs[event], "Invalid event!")

    local lines = {}

    for linenr, _ in pairs(callgraph.callgraphs[event].node_info[file]) do
        if linenr >= line_begin and linenr <= line_end then
            table.insert(lines, {file, linenr})
        end
    end

    local in_counts = callgraph.merge_in_counts(event, lines)
    local entries = {}
    local total_count = 0
    local max_count = 0

    for in_file, file_tbl in pairs(in_counts) do
        for in_line, count in pairs(file_tbl) do
            table.insert(entries, {"", in_file, in_line, count})
            total_count = total_count + count
            max_count = math.max(max_count, count)
        end
    end

    local function annotate_file(bufnr, fname)
        if not in_counts[fname] then
            return
        end

        for linenr, count in pairs(in_counts[fname]) do
            annotate.add_annotation(bufnr, linenr, count, total_count, max_count)
        end
    end

    pickers.new({}, {
        prompt_title = "",
        finder = hottest_table(entries, total_count),
        sorter = tconf.file_sorter{},
        previewer = annotated_previewer(annotate_file)
    }):find()
end

local function find_hottest()
    perfanno.with_event(find_hottest_lines)
end

local function find_hottest_syms()
    perfanno.with_event(find_hottest_symbols)
end

local function find_hottest_callers_function()
    perfanno.with_event(function()
        local file = vim.fn.expand("%:p"):gsub("/+", "/")
        local line_begin, line_end = treesitter.get_function_lines()

        if line_begin and line_end then
            find_hottest_callers(file, line_begin, line_end)
        end
    end)
end

local function find_hottest_callers_selection()
    perfanno.with_event(function()
        local file = vim.fn.expand("%:p"):gsub("/+", "/")
        local line_begin, _, line_end, _ = util.visual_selection_range()

        if line_begin and line_end then
            find_hottest_callers(file, line_begin, line_end)
        end
    end)
end

return telescope.register_extension {
    exports = {
        find_hottest_lines = find_hottest,
        find_hottest_symbols = find_hottest_syms,
        find_hottest_callers_function = find_hottest_callers_function,
        find_hottest_callers_selection = find_hottest_callers_selection,
    }
}
