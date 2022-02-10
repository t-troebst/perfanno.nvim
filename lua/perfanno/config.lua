-- config.lua
-- Stores the global configuration options of this plugin

local defaults = {
    -- List of highlights that will be used to highlight hot lines (or nil to disable highlighting)
    line_highlights = nil,
    -- Highlight used for virtual text annotations (or nil to disable virtual text)
    vt_highlight = nil,

    -- Annotation formats that can be cycled between via :PerfCycleFormat
    --   "percent" controls whether percentages or absolute counts should be displayed
    --   "format" is the format string that will be used to display counts / percentages
    --   "minimum" is the minimum value below which lines will not be annotated
    -- Note: this also controls what shows up in the telescope finders
    formats = {
        {percent = true, format = "%.2f%%", minimum = 0.5},
        {percent = false, format = "%d", minimum = 1}
    },

    -- Automatically annotate files after :PerfLoadFlat and :PerfLoadCallGraph
    annotate_after_load = true,

    -- Node type patterns used to find the function that surrounds the cursor
    ts_function_patterns = {
        -- These should work for most languages (at least those used with perf)
        default = {
            "function",
            "method",
        },
        -- Otherwise you can add patterns for specific languages like:
        -- weirdlang = {
        --     "weirdfunc",
        -- }
    },

    -- Internal, stores current state - do not touch!
    selected_format = 1,
    selected_event = nil,
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

    if fmt.percent then
        val = count / total * 100
    else
        val = count
    end

    if val >= fmt.minimum then
        return string.format(fmt.format, val)
    end  -- return nil
end

return M
