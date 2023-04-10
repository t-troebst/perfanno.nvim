--- Defines various utility functions used throughout the plugin.

local M = {}

--- Initialize table at key with value if its currently nil.
-- @param tab Table to initialize.
-- @param key Key where we will initialize.
-- @param value Value that will be set if tab[key] is nil.
function M.init(tab, key, value)
    if not tab[key] then
        tab[key] = value
    end
end

--- Rounds number to the closest integer.
-- @param f Number to round.
-- @return Closest integer.
function M.round(f)
    return math.floor(f + 0.5) -- good enough...
end

--- Iterator that iterates through consecutive pairs in a list.
-- @param list List to iterate over.
-- @return Pairwise iterator function.
function M.pairwise(list)
    local i = 0
    local n = #list - 1

    return function()
        i = i + 1

        if i <= n then
            return list[i], list[i + 1]
        end
    end
end

--- Computes minimum of two values but interprets nil as infinity.
-- @param x First value.
-- @param y Second value.
-- @return Minimum of x and y where nil compares larger than everything.
function M.min_nil(x, y)
    if x == nil then
        return y
    end

    if y == nil then
        return x
    end

    return math.min(x, y)
end

--- Computes minimum of two values but interprets nil as minus infinity.
-- @param x First value.
-- @param y Second value.
-- @return Maximum of x and y where nil compares smaller than everything.
function M.max_nil(x, y)
    if x == nil then
        return y
    end

    if y == nil then
        return x
    end

    return math.max(x, y)
end

--- Determines whether something is a Lua table.
-- @param tab Potential table.
-- @return true if tab is a table, false otherwise.
function M.is_table(tab)
    if type(tab) == "table" then
        return true
    end

    return false
end

--- Gets the range of the current visual selection.
-- @return start line, start column, end line, end column where lines and columns are both
--         inclusive, lines are 1-indexed and columns are 0-indexed.
function M.visual_selection_range()
    local _, csrow, cscol, _ = unpack(vim.fn.getpos("'<"))
    local _, cerow, cecol, _ = unpack(vim.fn.getpos("'>"))

    if csrow < cerow or (csrow == cerow and cscol <= cecol) then
        return csrow, cscol, cerow, cecol
    else
        return cerow, cecol, csrow, cscol
    end
end

local num_highlights = 0

function M.make_fg_highlight(color)
    num_highlights = num_highlights + 1
    vim.api.nvim_set_hl(0, "PerfAnno" .. num_highlights, { fg = color })

    return "PerfAnno" .. num_highlights
end

function M.make_bg_highlight(color)
    num_highlights = num_highlights + 1
    vim.api.nvim_set_hl(0, "PerfAnno" .. num_highlights, { bg = color })

    return "PerfAnno" .. num_highlights
end

function M.make_fg_highlights(start, stop, num)
    local colors = M.rgb_color_gradient({ M.hex_to_rgb(start) }, { M.hex_to_rgb(stop) }, num)
    local highlights = {}

    for _, color in ipairs(colors) do
        table.insert(highlights, M.make_fg_highlight(M.rgb_to_hex(unpack(color))))
    end

    return highlights
end

function M.make_bg_highlights(start, stop, num)
    local colors = M.rgb_color_gradient({ M.hex_to_rgb(start) }, { M.hex_to_rgb(stop) }, num)
    local highlights = {}

    for _, color in ipairs(colors) do
        table.insert(highlights, M.make_bg_highlight(M.rgb_to_hex(unpack(color))))
    end

    return highlights
end

function M.hex_to_rgb(hex)
    local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
    assert(r and g and b, "Invalid format!")

    return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

function M.rgb_to_hex(r, g, b)
    return string.format("#%02x%02x%02x", r, g, b)
end

function M.rgb_color_gradient(start, stop, num)
    if num == 1 then
        return { stop }
    end

    local colors = {}

    local r_start, g_start, b_start = unpack(start)
    local r_stop, g_stop, b_stop = unpack(stop)

    for i = 1, num do
        local color = {
            r_start + (r_stop - r_start) * i / num,
            g_start + (g_stop - g_start) * i / num,
            b_start + (b_stop - b_start) * i / num,
        }
        table.insert(colors, color)
    end

    return colors
end

return M
