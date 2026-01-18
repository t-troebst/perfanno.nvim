--- Uses treesitter to get current function / class context.

local config = require("perfanno.config")

local M = {}

---@class TSNode
---@field type fun(self: TSNode): string
---@field range fun(self: TSNode): integer, integer, integer, integer
---@field parent fun(self: TSNode): TSNode?

-- Gets treesitter node at a specific position in a buffer.
---@param bufnr number of the buffer.
---@param line number (1-indexed).
---@param column number (0-indexed).
---@return TSNode?
local function get_node_at_line(bufnr, line, column)
    local ok, root_tree = pcall(
        vim.treesitter.get_parser,
        bufnr,
        vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    )

    if not ok or not root_tree then
        return nil
    end

    local lang_tree = root_tree:language_for_range { line - 1, column, line - 1, column }

    ---@type TSNode?
    local root
    for _, tree in pairs(lang_tree:trees()) do
        root = tree:root()

        if root and vim.treesitter.is_in_node_range(root, line - 1, column) then
            break
        end
    end

    if not root then
        return nil
    end

    return root:named_descendant_for_range(line - 1, column, line - 1, column)
end

--- Gets lines of the smalled node surrounding given position whose type matches a pattern.
---@param bufnr number of the buffer, current if nil.
---@param linenr number (1-indexed).
---@param column number (0-indexed).
---@param type_patterns string[] List of lua patterns to apply to node types.
---@return integer?, integer? - start line, end line (1-indexed, inclusive) of first parent node that matches a pattern.
--         If no matching node was found, return nil.
function M.get_context_lines(bufnr, linenr, column, type_patterns)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local node = get_node_at_line(bufnr, linenr, column)

    while node do
        for _, pattern in ipairs(type_patterns) do
            if node:type():match(pattern) then
                local srow, _, erow, ecol = node:range()
                srow = srow + 1
                erow = erow + 1

                if ecol == 0 then
                    erow = erow - 1
                end

                return srow, erow
            end
        end
        node = node:parent()
    end -- return nil
end

--- Get lines of the function that surrounds a given position.
-- This function uses the patterns specified in the ts_function_patterns value
-- of the config to detect functions.
---@param bufnr? number to use, current if nil.
---@param linenr? number (1-indexed), current if nil.
---@param column? number (0-indexed), current if linenr is nil and 0 if column is nil.
---@return integer?, integer? - start line, end line (1-indexed, inclusive) of surrounding function, or nil if none was
--         found.
function M.get_function_lines(bufnr, linenr, column)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    if not linenr then
        ---@type number, number
        linenr, column = unpack(vim.api.nvim_win_get_cursor(0))
    else
        column = column or 0
    end

    -- Try to get the parser to check if treesitter is available
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
    if not ok or not parser then
        return nil
    end

    local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    local patterns = config.values.ts_function_patterns[lang]
        or config.values.ts_function_patterns.default
    return M.get_context_lines(bufnr, linenr, column, patterns)
end

return M
