local load_data = require("perfanno.load_data")
local M = {}
local buffers = {}

local function get_events()
    local events = {}

    for event, _ in pairs(load_data.annotations) do
        table.insert(events, event)
    end

    return events
end

local current_event = nil

function M.get_current_event()
    return current_event
end

function M.annotate_buffer(bnr, event, opts)
    if not bnr then
        bnr = vim.fn.bufnr("%")
    end

    local file = vim.fn.expand("#" .. bnr .. ":p")

    if not buffers[bnr] then
        buffers[bnr] = vim.api.nvim_create_namespace("perfanno_" .. bnr)
    else
        M.clear_buffer(bnr)
    end

    if not event then
        local events = get_events()

        if #events == 1 then
            event = events[1]
        else
            vim.ui.select(events, {prompt = "Select event type to annotate: "}, function(choice)
                if choice then
                    M.annotate_buffer(bnr, choice, opts)
                end
            end)

            return
        end
    end

    if load_data.annotations[event][file] then
        for linenr, data in pairs(load_data.annotations[event][file]) do
            if opts.highlights then
                local num_hls = #opts.highlights
                local i = math.floor(num_hls * data[2] + 0.5)

                if i > 0 then
                    vim.api.nvim_buf_add_highlight(bnr, buffers[bnr], opts.highlights[i], linenr - 1, 0, -1)
                end
            end

            if opts.virtual_text then
                local vopts = {
                    virt_text = {{data[1], opts.virtual_text.highlight}},
                    virt_text_pos = "eol"
                }

                vim.api.nvim_buf_set_extmark(bnr, buffers[bnr], linenr - 1, 0, vopts)
            end
        end
    end
end

function M.clear_buffer(bnr)
    if not bnr then
        bnr = vim.fn.bufnr("%")
    end

    if not buffers[bnr] then
        return
    end

    vim.api.nvim_buf_clear_namespace(bnr, buffers[bnr], 0, -1)
end

local toggle_on = false

function M.reannotate(bnr, opts)
    if current_event and toggle_on then
        M.annotate_buffer(bnr, current_event, opts)
    end
end

function M.annotate(event, opts)
    if not event then
        local events = get_events()

        if #events == 1 then
            event = events[1]
        else
            vim.ui.select(events, {prompt = "Select event type to annotate: "}, function(choice)
                if choice then
                    M.annotate(choice, opts)
                end
            end)

            return
        end
    end

    current_event = event
    toggle_on = true

    for _, bnr in ipairs(vim.api.nvim_list_bufs()) do
        M.reannotate(bnr, opts)
    end
end

function M.clear()
    current_event = nil
    toggle_on = false

    for _, bnr in ipairs(vim.api.nvim_list_bufs()) do
        M.clear_buffer(bnr)
    end
end

function M.toggle_annotations(opts)
    if toggle_on then
        toggle_on = false

        for _, bnr in ipairs(vim.api.nvim_list_bufs()) do
            M.clear_buffer(bnr)
        end
    else
        if not current_event then
            if load_data.is_loaded() then
                M.annotate(nil, opts)
                return
            end

            print("No annotations are loaded!")
            return
        end

        toggle_on = true

        for _, bnr in ipairs(vim.api.nvim_list_bufs()) do
            M.reannotate(bnr, opts)
        end
    end
end


return M
