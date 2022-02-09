local function load_raw_data(file, callgraph)
    if not file then
        file = "perf.data"
    end

    local esc = vim.fn.fnameescape(file)
    local cmd

    if callgraph then
        cmd = "perf report -g folded,0,caller,srcline,branch,count --no-children --full-source-path --stdio -i " .. esc
    else
        cmd = "perf report -F overhead,srcline --stdio --full-source-path -i " .. esc
    end


    local data_file = assert(io.popen(cmd, "r"))
    data_file:flush()
    local output = data_file:read("*all")
    data_file:close()

    return output
end

local function parse_call_graph(data, min)
    local result = {}
    local counts = {}
    local current_event = ""

    for line in data:gmatch("[^\r\n]+") do
        local cnt, event = line:match("# Samples: (%d+[KMB]?)%s+of event '(.*)'")

        if cnt and event then
            result[event] = {}
            counts[event] = 0
            current_event = event
        else
            local count, trace = line:match("^(%d+) (.*)$")

            if count and trace then
                counts[current_event] = counts[current_event] + count

                for file, linenr in trace:gmatch("(/.-):(%d+)") do
                    if not result[current_event][file] then
                        result[current_event][file] = {}
                    end

                    if not result[current_event][file][tonumber(linenr)] then
                        result[current_event][file][tonumber(linenr)] = 0
                    end

                    local cur_count = result[current_event][file][tonumber(linenr)]
                    result[current_event][file][tonumber(linenr)] = cur_count + count
                end
            end

        end
    end

    for event, event_dir in pairs(result) do
        for file, file_dir in pairs(event_dir) do
            for linenr, cnt in pairs(file_dir) do
                local pct = 100 * cnt / counts[event]

                if pct > min then
                    result[event][file][linenr] = pct
                else
                    result[event][file][linenr] = nil
                end
            end
        end
    end

    return result
end

local function parse_line_data(data, min)
    local result = {}
    local current_event = ""

    for line in data:gmatch("[^\r\n]+") do
        local num, event = line:match("# Samples: (%d+[KMB]?)%s+of event '(.*)'")

        if num then
            result[event] = {}
            current_event = event
        else
            local pct, file, linenr = line:match("%s*(%d+%.%d%d)%%%s+(.*):(%d+)")

            if pct and vim.startswith(file, "/") then
                if not result[current_event][file] then
                    result[current_event][file] = {}
                end

                if tonumber(pct) > min then
                    result[current_event][file][tonumber(linenr)] = tonumber(pct)
                end
            end
        end
    end

    return result
end

local function parse_data(data, callgraph, min)
    if not min then
        min = 0
    end

    if callgraph then
        return parse_call_graph(data, min)
    else
        return parse_line_data(data, min)
    end
end

local M = {}
M.annotations = {}
M.max_pcts = {}
local current_data = nil

local function set_max_pct()
    M.max_pcts = {}

    for event, event_dir in pairs(M.annotations) do
        local mp = 0

        for _, file_dir in pairs(event_dir) do
            for _, pct in pairs(file_dir) do
                mp = math.max(mp, pct)
            end
        end

        M.max_pcts[event] = mp
    end
end

function M.load_data(perf_data, callgraph, min)
    local perf_output

    if perf_data then
        if vim.fn.filereadable(perf_data) == 0 then
            print("Could not read file: " .. perf_data)
            return
        end

        perf_output = load_raw_data(perf_data, callgraph)
    elseif vim.fn.filereadable("perf.data") == 1 then
        perf_output = load_raw_data(perf_data, callgraph)
    else
        -- Can't find perf.data, ask user where it is
        local opts = {
            prompt = "Input path to perf.data: ",
            default = vim.fn.getcwd() .. "/",
            completion = "file"
        }

        vim.ui.input(opts, function(choice)
            if choice then
                M.load_data(choice, callgraph)
            end
        end)
        return
    end

    local data = parse_data(perf_output, callgraph, min)
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

    set_max_pct()
end

function M.is_loaded()
    return current_data ~= nil
end

function M.reload_data(callgraph, min)
    M.load_data(current_data, callgraph, min)
end

function M.print_annotations()
    for event, event_dir in pairs(M.annotations) do
        print("Event: " .. event)

        for file, file_dir in pairs(event_dir) do
            print("    File: " .. file)

            for linenr, pct in pairs(file_dir) do
                print("        Line " .. linenr .. " (" .. pct .. "%)")
            end
        end
    end
end

return M
