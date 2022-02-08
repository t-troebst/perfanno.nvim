local load_data = require("perfanno.load_data")
local M = {}
M.buffers = {}

local function get_events()
    local events = {}

    for event, _ in pairs(load_data.annotations) do
        table.insert(events, event)
    end

    return events
end


function M.annotate_buffer(bnr, event, opts)
    if not bnr then
        bnr = vim.fn.bufnr("%")
    end

    local file = vim.fn.expand("#" .. bnr .. ":p")

    if not M.buffers[bnr] then
        M.buffers[bnr] = vim.api.nvim_create_namespace("perfanno_" .. bnr)
    else
        M.clear_buffer(bnr)
    end

    if not event then
        local events = get_events()

        if #events == 1 then
            event = events[0]
        else
            vim.ui.select(events, {prompt = "Select event type to annotate:"}, function(choice)
                if choice then
                    M.annotate_buffer(bnr, choice, opts)
                end
            end)

            return
        end
    end

    if load_data.annotations[event][file] then
        local max_pct = 0

        for _, pct in pairs(load_data.annotations[event][file]) do
            max_pct = math.max(max_pct, pct)
        end

        for linenr, pct in pairs(load_data.annotations[event][file]) do

            if opts.highlights then
                local num_hls = #opts.highlights
                local i = math.floor(num_hls * pct / max_pct + 0.5)

                if i > 0 then
                    vim.api.nvim_buf_add_highlight(bnr, M.buffers[bnr], opts.highlights[i], linenr, 0, -1)
                end
            end

            if opts.virtual_text then
                local vopts = {
                    virt_text = {{pct .. "%", opts.virtual_text.highlight}},
                    virt_text_pos = "eol"
                }

                vim.api.nvim_buf_set_extmark(bnr, M.buffers[bnr], linenr, 0, vopts)
            end
        end
    end
end

function M.clear_buffer(bnr)
    if not bnr then
        bnr = vim.fn.bufnr("%")
    end

    if not M.buffers[bnr] then
        return
    end

    vim.api.nvim_buf_clear_namespace(bnr, M.buffers[bnr], 0, -1)
end

return M
