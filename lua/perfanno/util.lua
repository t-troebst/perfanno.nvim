-- util.lua
-- Defines various utility functions used throughout the plugin
local M = {}

function M.init(tab, key, value)
    if not tab[key] then
        tab[key] = value
    end
end

function M.round(f)
    return math.floor(f + 0.5)  -- good enough...
end

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

function M.min_nil(x, y)
    if x == nil then
        return y
    end

    if y == nil then
        return x
    end

    return math.min(x,  y)
end

function M.max_nil(x, y)
    if x == nil then
        return y
    end

    if y == nil then
        return x
    end

    return math.max(x,  y)
end

function M.is_table(tab)
    if type(tab) == "table" then
        return true
    end

    return false
end

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
    vim.highlight.create("PerfAnno" .. num_highlights, {guifg = color})

    return "PerfAnno" .. num_highlights
end

function M.make_bg_highlight(color)
    num_highlights = num_highlights + 1
    vim.highlight.create("PerfAnno" .. num_highlights, {guibg = color})

    return "PerfAnno" .. num_highlights
end

function M.make_fg_highlights(start, stop, num)
    local colors = M.rgb_color_gradient({M.hex_to_rgb(start)}, {M.hex_to_rgb(stop)}, num)
    local highlights = {}

    for _, color in ipairs(colors) do
        table.insert(highlights, M.make_fg_highlight(M.rgb_to_hex(unpack(color))))
    end

    return highlights
end

function M.make_bg_highlights(start, stop, num)
    local colors = M.rgb_color_gradient({M.hex_to_rgb(start)}, {M.hex_to_rgb(stop)}, num)
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
        return {stop}
    end

    local colors = {}

    local r_start, g_start, b_start = unpack(start)
    local r_stop, g_stop, b_stop = unpack(stop)

    for i = 1, num do
        local color = {r_start + (r_stop - r_start) * i / num,
                       g_start + (g_stop - g_start) * i / num,
                       b_start + (b_stop - b_start) * i / num}
        table.insert(colors, color)
    end

    return colors
end

return M
