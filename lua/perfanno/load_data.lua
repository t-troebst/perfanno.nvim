local function load_raw_data(file, callgraph)
    if not file then
        file = "perf.data"
    end

    local esc = vim.fn.fnameescape(file)
    local cmd

    if callgraph then
        cmd = "perf report -g folded,0,caller,srcline,branch,count --no-children --full-source-path --stdio -i " .. esc
    else
        cmd = "perf report -g none -F sample,srcline --stdio --full-source-path -i " .. esc
    end


    local data_file = assert(io.popen(cmd, "r"))
    data_file:flush()
    local output = data_file:read("*all")
    data_file:close()

    return output
end

local function format_annotations(data, counts, opts)
    for event, event_dir in pairs(data) do
        for file, file_dir in pairs(event_dir) do
            for linenr, cnt in pairs(file_dir) do
                local rel = cnt / counts[event][2]

                if opts.numbers == "percent" then
                    cnt = 100 * cnt / counts[event][1]
                end

                if cnt > opts.minimum then
                    data[event][file][linenr] = {string.format(opts.format, cnt), rel}
                else
                    data[event][file][linenr] = nil
                end
            end
        end
    end
end

local function parse_call_graph(data)
    local result = {}
    local counts = {}
    local current_event = ""

    for line in data:gmatch("[^\r\n]+") do
        local cnt, event = line:match("# Samples: (%d+[KMB]?)%s+of event '(.*)'")

        if cnt and event then
            result[event] = {}
            counts[event] = {0, 0}
            current_event = event
        else
            local count, trace = line:match("^(%d+) (.*)$")

            if count and trace then
                counts[current_event][1] = counts[current_event][1] + count

                for file, linenr in trace:gmatch("(/.-):(%d+)") do
                    if not result[current_event][file] then
                        result[current_event][file] = {}
                    end

                    linenr = tonumber(linenr)

                    if not result[current_event][file][linenr] then
                        result[current_event][file][linenr] = 0
                    end

                    local cur_count = result[current_event][file][linenr]
                    result[current_event][file][linenr] = cur_count + count
                    counts[current_event][2] = math.max(counts[current_event][2], cur_count + count)
                end
            end

        end
    end

    return result, counts
end

local function parse_line_data(data)
    local result = {}
    local counts = {}
    local current_event = ""

    for line in data:gmatch("[^\r\n]+") do
        local num, event = line:match("# Samples: (%d+[KMB]?)%s+of event '(.*)'")

        if num then
            result[event] = {}
            counts[event] = {0, 0}
            current_event = event
        else
            local count, file, linenr = line:match("^%s*(%d+)%s+(.*):(%d+)")

            if count and vim.startswith(file, "/") then
                counts[current_event][1] = counts[current_event][1] + count

                if not result[current_event][file] then
                    result[current_event][file] = {}
                end

                linenr = tonumber(linenr)

                if not result[current_event][file][linenr] then
                    result[current_event][file][linenr] = 0
                end

                local cur_count = result[current_event][file][linenr]
                result[current_event][file][linenr] = cur_count + count
                counts[current_event][2] = math.max(counts[current_event][2], cur_count + count)
            else
                local address_count = line:match("^%s*(%d+)%s+.*%+%d+")

                if address_count then
                    counts[current_event][1] = counts[current_event][1] + address_count
                end
            end
        end
    end

    return result, counts
end

local function parse_data(data, callgraph, opts)
    if callgraph then
        local result, counts = parse_call_graph(data)
        format_annotations(result, counts, opts.callgraph)
        return result
    else
        local result, counts = parse_line_data(data)
        format_annotations(result, counts, opts.flat)
        return result
    end
end

local M = {}
M.annotations = {}
local current_data = nil

function M.load_data(perf_data, callgraph, opts)
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
        local input_opts = {
            prompt = "Input path to perf.data: ",
            default = vim.fn.getcwd() .. "/",
            completion = "file"
        }

        vim.ui.input(input_opts, function(choice)
            if choice then
                M.load_data(choice, callgraph, opts)
            end
        end)
        return
    end

    current_data = perf_data
    M.annotations = vim.tbl_extend("force", M.annotations, parse_data(perf_output, callgraph, opts))
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
