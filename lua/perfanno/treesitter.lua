-- treesitter.lua
-- Uses treesitter to get current function / class context

local config = require("perfanno.config")

local ok1, ts_utils = pcall(require, "nvim-treesitter.ts_utils")
local ok2, parsers = pcall(require, "nvim-treesitter.parsers")

if not (ok1 and ok2) then
    return
end

local M = {}

local function get_node_at_line(bufnr, linenr, column)
    local root_tree = parsers.get_parser(bufnr)

    if not root_tree then
        return nil
    end

    local root = ts_utils.get_root_for_position(linenr - 1, column, root_tree)

    if not root then
        return nil
    end

    return root:named_descendant_for_range(linenr - 1, column, linenr - 1, column)
end

function M.get_context_lines(bufnr, linenr, column, type_patterns)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local lang = parsers.get_buf_lang(bufnr)

    if not parsers.has_parser(lang) then
        return nil
    end

    local node = get_node_at_line(bufnr, linenr, column)
    repeat
        for _, pattern in ipairs(type_patterns) do
            if node:type():match(pattern) then
                local srow, _, erow, _ = ts_utils.get_vim_range({node:range()}, bufnr)

                return srow, erow
            end
        end
        node = node:parent()
    until not node  -- return nil
end

function M.get_function_lines(bufnr, linenr, column)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local lang = parsers.get_buf_lang(bufnr)

    if not linenr then
        linenr, column = unpack(vim.api.nvim_win_get_cursor(0))
    else
        column = column or 0
    end

    if not parsers.has_parser(lang) then
        return nil
    end

    local patterns = config.values.ts_function_patterns[lang] or config.values.ts_function_patterns.default

    return M.get_context_lines(bufnr, linenr, column, patterns)
end

return M
