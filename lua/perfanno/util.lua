-- util.lua
-- Defines various utility functions used throughout the plugin

local M = {}

function M.init(tab, key, value)
    if not tab[key] then
        tab[key] = value
    end
end

function M.pairwise(list)
    local i = 0
    local n = table.getn(list) - 1

    return function()
        i = i + 1

        if i <= n then
            return list[i], list[i + 1]
        end
    end
end

return M
