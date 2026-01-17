-- Minimal init for running tests with plenary.nvim
-- Usage: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

-- Add plenary and this plugin to runtimepath
local plenary_path = vim.fn.stdpath("data") .. "/site/pack/vendor/start/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 0 then
    -- Try common alternative locations
    local alt_paths = {
        vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim"),
        vim.fn.expand("~/.local/share/nvim/site/pack/packer/start/plenary.nvim"),
    }
    for _, path in ipairs(alt_paths) do
        if vim.fn.isdirectory(path) == 1 then
            plenary_path = path
            break
        end
    end
end

vim.opt.rtp:prepend(plenary_path)
vim.opt.rtp:prepend(vim.fn.getcwd())

-- Mock vim.loop.fs_realpath to return input unchanged (avoids filesystem dependency in tests)
local original_fs_realpath = vim.loop.fs_realpath
vim.loop.fs_realpath = function(path)
    -- For test paths, just return the path as-is
    if path and path:match("^/tmp/") then
        return path
    end
    -- For real paths, use the original function
    return original_fs_realpath(path)
end

-- Minimal settings
vim.o.swapfile = false
vim.o.backup = false
vim.o.writebackup = false
