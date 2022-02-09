local ld = require("perfanno.load_data")
local sa = require("perfanno.show_annotations")

local M = {}

-- Default highlights were generated with this tool:
-- https://meyerweb.com/eric/tools/color-blend/#24273B:CC3300:4:hex
-- This blends between the TokyoNight background and a nice red
local defaults = {
    colors = {"#46292F", "#672C23", "#892E18", "#AA310C", "#CC3300"},
    highlights = nil,
    virtual_text = {color = "#CC3300", highlight = nil},
    auto_annotate = true,
    minimum_pct = 0.1,
}

M.opts = defaults

function M.setup(opts)
    if opts then
        vim.tbl_extend("force", M.opts, opts)
    end

    -- Create highlight for virtual text if a color was given
    if M.opts.virtual_text and not M.opts.virtual_text.highlight then
        M.opts.virtual_text.highlight = "PerfAnnoVT"
        vim.highlight.create("PerfAnnoVT", {guifg = M.opts.virtual_text.color}, false)
    end

    -- Create background highlights if colors were given
    if M.opts.colors and not M.opts.highlights then
        M.opts.highlights = {}

        for i, color in ipairs(M.opts.colors) do
            vim.highlight.create("PerfAnno" .. i, {guibg = color}, false)
            table.insert(M.opts.highlights, "PerfAnno" .. i)
        end
    end

    -- TODO: switch to vim.api.nvim_add_user_command once its available
    vim.cmd[[command PerfAnnoLoadFlat :lua require("perfanno").load_data(nil, false)]]
    vim.cmd[[command PerfAnnoLoadCallGraph :lua require("perfanno").load_data(nil, true)]]
    vim.cmd[[command PerfAnnoAnnotateBuffer :lua require("perfanno").annotate_buffer()]]
    vim.cmd[[command PerfAnnoClearBuffer :lua require("perfanno").clear_buffer()]]
    vim.cmd[[command PerfAnnoAnnotateFlat :lua require("perfanno").annotate()]]
    vim.cmd[[command PerfAnnoAnnotateCallGraph :lua require("perfanno").annotate(nil, true)]]
    vim.cmd[[command PerfAnnoToggleAnnotations :lua require("perfanno").toggle_annotations()]]
    vim.cmd[[command PerfAnnoClear :lua require("perfanno").clear()]]
    vim.cmd[[command PerfAnnoFindHottest :lua require("perfanno.telescope").find_hottest()]]

    if M.opts.auto_annotate then
        vim.cmd[[autocmd BufRead * :lua require("perfanno").reannotate()]]
    end
end

function M.load_data(data, callgraph)
    ld.load_data(data, callgraph, M.opts.minimum_pct)
end

function M.annotate_buffer(bnr, event)
    sa.annotate_buffer(bnr, event, M.opts)
end

function M.annotate(event, callgraph)
    ld.reload_data(callgraph, M.opts.minimum_pct)
    sa.annotate(event, M.opts)
end

function M.reannotate(bnr)
    sa.reannotate(bnr, M.opts)
end

function M.toggle_annotations()
    sa.toggle_annotations(M.opts)
end

M.clear_buffer = sa.clear_buffer
M.clear = sa.clear

return M
