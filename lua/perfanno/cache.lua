--- Deals with storing / loading callgraphs from the cache

local M = {}

-- Initialize plugin cache directory
local plugin_cache = vim.fn.stdpath("cache") .. "/perfanno"
if vim.fn.isdirectory(plugin_cache) == 0 then
    vim.fn.mkdir(plugin_cache, "p")
end

--- Ugly hack that deep-replaces number indices by string indices in a Lua table.
-- Note: this is required because we cannot convert sparse arrays to JSON.
-- @param data Lua object, function does nothing on non-tables.
-- @return Deep-copied table with no number indices.
local function stringify_table(data)
    if type(data) ~= "table" then
        return data
    end

    local result = {}

    for key, value in pairs(data) do
        if type(key) == "number" then
            result["<NUM:" .. tostring(key) .. ">"] = stringify_table(value)
        else
            result[key] = stringify_table(value)
        end
    end

    return result
end

--- Inverse of stringify_table.
-- @param data Lua object, function returns nothing on non-tables.
-- @return Deep-copied table with number indices.
local function destringify_table(data)
    if type(data) ~= "table" then
        return data
    end

    local result = {}

    for key, value in pairs(data) do
        local n = key:match("^<NUM:(%d*)>$")
        if n then
            result[tonumber(n)] = destringify_table(value)
        else
            result[key] = destringify_table(value)
        end
    end

    return result
end

--- Stores json data in a file
-- @param file Filename to use
-- @param data Lua table to convert
local function store_json(file, data)
    local data_json = vim.json.encode(stringify_table(data))
    local file_handle = io.open(file, "w")
    if not file_handle then
        vim.notify("Could not open file for writing: " .. file, vim.log.levels.ERROR)
        return
    end

    file_handle:write(data_json)
    file_handle:close()
end

--- Loads json from a file
-- @param file Filename to use
-- @return Lua table
local function load_json(file)
    local file_handle = io.open(file)
    if not file_handle then
        return {}
    end

    local data_json = file_handle:read("*all")
    file_handle:close()
    return destringify_table(vim.json.decode(data_json))
end

local index_file = plugin_cache .. "/index.json"
local index = {}

--- Stores the index in the designated index.json file
function M.store_index()
    store_json(index_file, index)
end

--- Loads the index from index.json
-- @return Newly loaded index
function M.load_index()
    index = load_json(index_file)
    return index
end

--- Suggests a filename to store a callgraph in the cache directory
-- @return Filename of the form <cache>/perfanno/callgraph.<num>.json
function M.suggest_filename()
    local nums = {}

    for _, entry in pairs(index) do
        local n = entry.file:match("/callgraph%.(%d*)%.json$")
        if n then
            table.insert(nums, tonumber(n))
        end
    end

    table.sort(nums)

    local min_free = 1
    for _, n in ipairs(nums) do
        if n == min_free then
            min_free = min_free + 1
        else
            return plugin_cache .. "/callgraph." .. tostring(min_free) .. ".json"
        end
    end

    return plugin_cache .. "/callgraph." .. tostring(min_free) .. ".json"
end

--- Stores callgraph data in file and index.
-- @param data Callgraph data lua table.
-- @param name Name for the index.
-- @param file Filename to save in or nil in which case we use suggest_filename().
function M.store_callgraph(data, name, file)
    file = file or M.suggest_filename()
    index[name] = {
        file = file,
        last_modified = vim.fn.localtime(),
    }

    store_json(file, data)
    return file
end

--- Loads callgraph data.
-- Note: this does not actually load the traces yet (nor does it annotate)!
-- @param name Name of callgraph in index.
-- @return Callgraph data or nil if not found.
function M.load_callgraph(name)
    if not index[name] then
        return nil
    end

    return load_json(index[name].file)
end

--- Deletes callgraph from index and disk.
-- @param name Name of callgraph to delete.
-- @return Filename of deleted callgraph or nil if not found.
function M.delete_callgraph(name)
    if index[name] then
        local file = index[name].file
        os.remove(file)
        index[name] = nil
        return file
    end

    return nil
end

return M
