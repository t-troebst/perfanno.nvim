-- config.lua
-- Stores the global configuration options of this plugin

local defaults = {
    line_highlights = nil,
    vt_highlight = nil,
    formats = {{relative = true, format = "%.2f%%", minimum = 0.5}, {relative = false, format = "%d", minimum = 1}},

    annotate_after_load = true,

    selected_format = 1,
    selected_event = nil,

    ts_function_patterns = {
        default = {
            "function",
            "method"
        }
    }
}

local M = vim.deepcopy(defaults)

function M.load(opts)
    for key, value in pairs(opts) do
        M[key] = vim.deepcopy(value)
    end
end

function M.format(count, total)
    local fmt = M.formats[M.selected_format]
    local val

    if fmt.relative then
        val = count / total * 100
    else
        val = count
    end

    if val >= fmt.minimum then
        return string.format(fmt.format, val)
    end  -- return nil
end

return M
