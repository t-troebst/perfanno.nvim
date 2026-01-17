local annotate = require("perfanno.annotate")
local callgraph = require("perfanno.callgraph")
local config = require("perfanno.config")

describe("annotate", function()
    local namespace_id

    before_each(function()
        -- Reset callgraph state
        callgraph.callgraphs = nil
        callgraph.events = nil

        -- Get the namespace used by annotate module
        namespace_id = vim.api.nvim_create_namespace("perfanno.annotations")

        -- Configure for testing with simple format
        config.selected_format = 1
        config.selected_event = nil
        config.values.formats = {
            { percent = false, format = "%d", minimum = 0 },
        }
        config.values.line_highlights = { "PerfAnnoLo", "PerfAnnoHi" }
        config.values.vt_highlight = "PerfAnnoVT"

        -- Clear toggled state by calling clear()
        annotate.clear()
    end)

    describe("add_annotation", function()
        it("should create line highlight extmark", function()
            local bnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(bnr, 0, -1, false, { "line 1" })

            annotate.add_annotation(bnr, 1, 100, 100, 100)

            local extmarks =
                vim.api.nvim_buf_get_extmarks(bnr, namespace_id, 0, -1, { details = true })

            -- Find extmark with hl_group
            local found_highlight = false
            for _, ext in ipairs(extmarks) do
                local details = ext[4]
                if details and details.hl_group then
                    found_highlight = true
                    assert.are.equal(0, ext[2]) -- row 0 (1-indexed line 1)
                end
            end
            assert.is_true(found_highlight)

            vim.api.nvim_buf_delete(bnr, { force = true })
        end)

        it("should create virtual text extmark", function()
            local bnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(bnr, 0, -1, false, { "line 1" })

            annotate.add_annotation(bnr, 1, 50, 100, 100)

            local extmarks =
                vim.api.nvim_buf_get_extmarks(bnr, namespace_id, 0, -1, { details = true })

            -- Find extmark with virt_text
            local found_virt_text = false
            for _, ext in ipairs(extmarks) do
                local details = ext[4]
                if details and details.virt_text then
                    found_virt_text = true
                    -- Format is "%d" so count 50 should show as "50"
                    assert.are.equal("50", details.virt_text[1][1])
                end
            end
            assert.is_true(found_virt_text)

            vim.api.nvim_buf_delete(bnr, { force = true })
        end)

        it("should use correct highlight based on count ratio", function()
            local bnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(bnr, 0, -1, false, { "line 1" })

            -- Max count = 100, count = 100 should use the highest highlight (index 2)
            annotate.add_annotation(bnr, 1, 100, 100, 100)

            local extmarks =
                vim.api.nvim_buf_get_extmarks(bnr, namespace_id, 0, -1, { details = true })

            local found_hl_group = nil
            for _, ext in ipairs(extmarks) do
                local details = ext[4]
                if details and details.hl_group then
                    found_hl_group = details.hl_group
                    break
                end
            end
            assert.are.equal("PerfAnnoHi", found_hl_group)

            vim.api.nvim_buf_delete(bnr, { force = true })
        end)

        it("should use lowest highlight for lowest count", function()
            local bnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(bnr, 0, -1, false, { "line 1" })

            -- count = 0, max_count = 100 should use the lowest highlight (index 1)
            annotate.add_annotation(bnr, 1, 0, 100, 100)

            local extmarks =
                vim.api.nvim_buf_get_extmarks(bnr, namespace_id, 0, -1, { details = true })

            local found_hl_group = nil
            for _, ext in ipairs(extmarks) do
                local details = ext[4]
                if details and details.hl_group then
                    found_hl_group = details.hl_group
                    break
                end
            end
            assert.are.equal("PerfAnnoLo", found_hl_group)

            vim.api.nvim_buf_delete(bnr, { force = true })
        end)

        it("should not create line highlight when line_highlights is nil", function()
            config.values.line_highlights = nil
            local bnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(bnr, 0, -1, false, { "line 1" })

            annotate.add_annotation(bnr, 1, 100, 100, 100)

            local extmarks =
                vim.api.nvim_buf_get_extmarks(bnr, namespace_id, 0, -1, { details = true })

            -- Should only have virtual text, no line highlight
            for _, ext in ipairs(extmarks) do
                local details = ext[4]
                if details then
                    assert.is_nil(details.hl_group)
                end
            end

            vim.api.nvim_buf_delete(bnr, { force = true })
        end)

        it("should not create virtual text when vt_highlight is nil", function()
            config.values.vt_highlight = nil
            local bnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(bnr, 0, -1, false, { "line 1" })

            annotate.add_annotation(bnr, 1, 100, 100, 100)

            local extmarks =
                vim.api.nvim_buf_get_extmarks(bnr, namespace_id, 0, -1, { details = true })

            -- Should only have line highlight, no virtual text
            for _, ext in ipairs(extmarks) do
                local details = ext[4]
                if details then
                    assert.is_nil(details.virt_text)
                end
            end

            vim.api.nvim_buf_delete(bnr, { force = true })
        end)

        it("should skip annotation when count is below minimum threshold", function()
            config.values.formats = {
                { percent = false, format = "%d", minimum = 10 },
            }
            local bnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(bnr, 0, -1, false, { "line 1" })

            -- Count 5 is below minimum 10
            annotate.add_annotation(bnr, 1, 5, 100, 100)

            local extmarks =
                vim.api.nvim_buf_get_extmarks(bnr, namespace_id, 0, -1, { details = true })

            -- No extmarks should be created
            assert.are.equal(0, #extmarks)

            vim.api.nvim_buf_delete(bnr, { force = true })
        end)

        it("should format count as percentage when configured", function()
            config.values.formats = {
                { percent = true, format = "%.1f%%", minimum = 0 },
            }
            local bnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(bnr, 0, -1, false, { "line 1" })

            -- count=25, total=100 should show as 25.0%
            annotate.add_annotation(bnr, 1, 25, 100, 100)

            local extmarks =
                vim.api.nvim_buf_get_extmarks(bnr, namespace_id, 0, -1, { details = true })

            local found_virt_text = nil
            for _, ext in ipairs(extmarks) do
                local details = ext[4]
                if details and details.virt_text then
                    found_virt_text = details.virt_text[1][1]
                    break
                end
            end
            assert.are.equal("25.0%", found_virt_text)

            vim.api.nvim_buf_delete(bnr, { force = true })
        end)
    end)

    describe("clear_buffer", function()
        it("should remove all extmarks from buffer", function()
            local bnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(bnr, 0, -1, false, { "line 1", "line 2" })

            annotate.add_annotation(bnr, 1, 100, 100, 100)
            annotate.add_annotation(bnr, 2, 50, 100, 100)

            -- Verify extmarks exist before clearing
            local extmarks_before = vim.api.nvim_buf_get_extmarks(bnr, namespace_id, 0, -1, {})
            assert.is_true(#extmarks_before > 0)

            annotate.clear_buffer(bnr)

            local extmarks_after = vim.api.nvim_buf_get_extmarks(bnr, namespace_id, 0, -1, {})
            assert.are.equal(0, #extmarks_after)

            vim.api.nvim_buf_delete(bnr, { force = true })
        end)
    end)

    describe("annotate_buffer", function()
        it("should annotate all lines from callgraph data", function()
            local bnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(bnr, 0, -1, false, { "line 1", "line 2", "line 3" })

            -- Set buffer name to a known path
            local test_file = "/tmp/test_annotate.lua"
            vim.api.nvim_buf_set_name(bnr, test_file)

            -- Load traces for this file
            callgraph.load_traces {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = test_file, linenr = 1 },
                            { symbol = "foo", file = test_file, linenr = 2 },
                        },
                    },
                },
            }
            config.selected_event = "cycles"

            annotate.annotate_buffer(bnr, "cycles")

            local extmarks =
                vim.api.nvim_buf_get_extmarks(bnr, namespace_id, 0, -1, { details = true })

            -- Should have extmarks for lines 1 and 2 (both line highlight and virtual text)
            -- With 2 lines and both line_highlights and vt_highlight enabled, we expect 4 extmarks
            assert.is_true(#extmarks >= 2)

            -- Check that we have extmarks on rows 0 and 1
            local rows_with_extmarks = {}
            for _, ext in ipairs(extmarks) do
                rows_with_extmarks[ext[2]] = true
            end
            assert.is_true(rows_with_extmarks[0])
            assert.is_true(rows_with_extmarks[1])

            vim.api.nvim_buf_delete(bnr, { force = true })
        end)

        it("should return false for files not in callgraph", function()
            local bnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(bnr, 0, -1, false, { "line 1" })
            vim.api.nvim_buf_set_name(bnr, "/tmp/unknown_file.lua")

            -- Load traces for a different file
            callgraph.load_traces {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/other_file.lua", linenr = 1 },
                        },
                    },
                },
            }
            config.selected_event = "cycles"

            local result = annotate.annotate_buffer(bnr, "cycles")

            assert.is_false(result)

            vim.api.nvim_buf_delete(bnr, { force = true })
        end)

        it("should clear existing annotations before adding new ones", function()
            local bnr = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(bnr, 0, -1, false, { "line 1", "line 2" })

            local test_file = "/tmp/test_clear_before.lua"
            vim.api.nvim_buf_set_name(bnr, test_file)

            -- Add some manual annotations first
            annotate.add_annotation(bnr, 1, 999, 999, 999)

            -- Load traces that only annotate line 2
            callgraph.load_traces {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "foo", file = test_file, linenr = 2 },
                        },
                    },
                },
            }
            config.selected_event = "cycles"

            annotate.annotate_buffer(bnr, "cycles")

            local extmarks =
                vim.api.nvim_buf_get_extmarks(bnr, namespace_id, 0, -1, { details = true })

            -- Should only have extmarks on row 1 (line 2), not row 0
            for _, ext in ipairs(extmarks) do
                assert.are.equal(1, ext[2]) -- all extmarks should be on row 1
            end

            vim.api.nvim_buf_delete(bnr, { force = true })
        end)
    end)

    describe("is_toggled", function()
        it("should return false initially", function()
            assert.is_false(annotate.is_toggled())
        end)

        it("should return true after annotate() is called", function()
            -- Need loaded callgraph for annotate to work
            callgraph.load_traces {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.lua", linenr = 1 },
                        },
                    },
                },
            }
            config.selected_event = "cycles"

            annotate.annotate("cycles")

            assert.is_true(annotate.is_toggled())
        end)

        it("should return false after clear() is called", function()
            callgraph.load_traces {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.lua", linenr = 1 },
                        },
                    },
                },
            }
            config.selected_event = "cycles"

            annotate.annotate("cycles")
            annotate.clear()

            assert.is_false(annotate.is_toggled())
        end)
    end)

    describe("should_annotate", function()
        it("should return false when callgraph is not loaded", function()
            assert.is_false(annotate.should_annotate())
        end)

        it("should return false when selected_event is nil", function()
            callgraph.load_traces {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.lua", linenr = 1 },
                        },
                    },
                },
            }
            config.selected_event = nil

            assert.is_false(annotate.should_annotate())
        end)

        it("should return false when not toggled on", function()
            callgraph.load_traces {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.lua", linenr = 1 },
                        },
                    },
                },
            }
            config.selected_event = "cycles"

            -- Not toggled yet
            assert.is_false(annotate.should_annotate())
        end)

        it("should return true when callgraph loaded, event selected, and toggled on", function()
            callgraph.load_traces {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.lua", linenr = 1 },
                        },
                    },
                },
            }
            config.selected_event = "cycles"
            annotate.annotate("cycles")

            assert.is_true(annotate.should_annotate())
        end)
    end)

    describe("toggle_annotations", function()
        it("should turn annotations on when toggled off", function()
            callgraph.load_traces {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.lua", linenr = 1 },
                        },
                    },
                },
            }
            config.selected_event = "cycles"

            assert.is_false(annotate.is_toggled())
            annotate.toggle_annotations("cycles")
            assert.is_true(annotate.is_toggled())
        end)

        it("should turn annotations off when toggled on", function()
            callgraph.load_traces {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.lua", linenr = 1 },
                        },
                    },
                },
            }
            config.selected_event = "cycles"

            annotate.annotate("cycles")
            assert.is_true(annotate.is_toggled())
            annotate.toggle_annotations("cycles")
            assert.is_false(annotate.is_toggled())
        end)
    end)
end)
