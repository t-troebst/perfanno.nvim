local M = {}


local function get_events()
    local events = {}

    for event, _ in pairs(PerfAnnotations) do
        table.insert(events, event)
    end

    return events
end

function M.annotate_buffer(bnr, event)
    if not bnr then
        bnr = vim.fn.bufnr("%")
    end

    local file = vim.fn.expand("#" .. bnr .. ":p")

    if not PerfAnnoBuffers[bnr] then
        PerfAnnoBuffers[bnr] = vim.api.nvim_create_namespace("perfanno_" .. bnr)
    else
        M.clear_buffer(bnr)
    end

    if not event then
        local events = get_events()

        vim.ui.select(events, {prompt = "Select event type to annotate:"}, function(choice)
            if choice then
                M.annotate_buffer(bnr, choice)
            end
        end)

        return
    end

    if PerfAnnotations[event][file] then
        max_pct = 0

        for _, pct in pairs(PerfAnnotations[event][file]) do
            max_pct = math.max(max_pct, pct)
        end

        for linenr, pct in pairs(PerfAnnotations[event][file]) do
            local i = math.floor(5 * pct / max_pct + 0.5)

            if i > 0 then
                local hl = "PerfAnno" .. i
                vim.api.nvim_buf_add_highlight(bnr, PerfAnnoBuffers[bnr], hl, linenr, 0, -1)
            end

            local opts = {
                virt_text = {{pct .. "%", "ErrorMsg"}},
                virt_text_pos = "eol"
            }

            vim.api.nvim_buf_set_extmark(bnr, PerfAnnoBuffers[bnr], linenr, 0, opts)
        end
    end
end

function M.clear_buffer(bnr)
    if not bnr then
        bnr = vim.fn.bufnr("%")
    end

    if not PerfAnnoBuffers[bnr] then
        return
    end

    vim.api.nvim_buf_clear_namespace(bnr, PerfAnnoBuffers[bnr], 0, -1)
end

return M
