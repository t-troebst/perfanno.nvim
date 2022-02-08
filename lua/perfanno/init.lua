PerfAnnotations = {} -- Stores actual annotation information
PerfAnnoBuffers = {} -- Stores namespaces for buffers that we are using

-- Default highlights were generated with this tool:
-- https://meyerweb.com/eric/tools/color-blend/#24273B:CC3300:4:hex
-- This blends between the TokyoNight background and a nice red

vim.highlight.create("PerfAnno1", {guibg = "#46292F"}, false)
vim.highlight.create("PerfAnno2", {guibg = "#672C23"}, false)
vim.highlight.create("PerfAnno3", {guibg = "#892E18"}, false)
vim.highlight.create("PerfAnno4", {guibg = "#AA310C"}, false)
vim.highlight.create("PerfAnno5", {guibg = "#CC3300"}, false)
