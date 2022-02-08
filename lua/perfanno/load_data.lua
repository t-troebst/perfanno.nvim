local function load_raw_data(file)
    if not file then
        file = "perf.data"
    end

    local data_file = assert(io.popen("perf report -F overhead,srcline --stdio --full-source-path -i " .. file, "r"))
    data_file:flush()
    local output = data_file:read("*all")
    data_file:close()

    return output
end

local function parse_data(data)
    local result = {}
    local current_event = ""

    for line in data:gmatch("[^\r\n]+") do
        local num, event = line:match("# Samples: (%d+[KMB]?)%s+of event '(.*)'")

        if num then
            result[event] = {}
            current_event = event
        end

        local pct, file, linenr = line:match("%s*(%d+%.%d%d)%%%s+(.*):(%d+)")
        if pct and file ~= "??" then
            if not result[current_event][file] then
                result[current_event][file] = {}
            end
            result[current_event][file][tonumber(linenr)] = tonumber(pct)
        end
    end

    return result
end

local M = {}

M.annotations = {}

local current_data = nil

function M.load_data(perf_data)
    local data

    if perf_data then
        if vim.fn.filereadable(perf_data) == 0 then
            print("Could not read file: " .. perf_data)
            return
        end

        data = parse_data(load_raw_data(perf_data))
    elseif vim.fn.filereadable("perf.data") == 1 then
        data = parse_data(load_raw_data(perf_data))
    else
        -- Can't find perf.data, ask user where it is
        local opts = {
            prompt = "Input path to perf.data: ",
            default = vim.fn.getcwd(),
            completion = "file"
        }

        vim.ui.input(opts, function(choice)
            if choice then
                M.load_data(choice)
            end
        end)
        return
    end

    current_data = perf_data

    -- Update annotations
    -- Note: we currently do not delete potentially outdated files because the user
    -- might be running two different annotations at the same time
    for event, event_dir in pairs(data) do
        if not M.annotations[event] then
            M.annotations[event] = {}
        end

        for file, file_dir in pairs(event_dir) do
            M.annotations[event][file] = file_dir
        end
    end
end

function M.reload_data()
    M.load_data(current_data)
end

function M.print_annotations()
    for event, event_dir in pairs(M.annotations) do
        print("Event: " .. event)

        for file, file_dir in pairs(event_dir) do
            print("    File: " .. file)

            for linenr, pct in pairs(file_dir) do
                print("        Line: " .. linenr .. " (" .. pct .. "%)")
            end
        end
    end
end

return M
