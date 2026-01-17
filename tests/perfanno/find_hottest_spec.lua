local callgraph = require("perfanno.callgraph")
local find_hottest = require("perfanno.find_hottest")
local config = require("perfanno.config")

describe("find_hottest", function()
    before_each(function()
        -- Reset callgraph state
        callgraph.callgraphs = nil
        callgraph.events = nil

        -- Configure low threshold so all entries pass filtering
        config.selected_format = 1
        config.values.formats = {
            { percent = false, format = "%d", minimum = 0 },
        }
    end)

    describe("hottest_lines_table", function()
        it("should return entries sorted by count descending", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 5,
                        frames = {
                            { symbol = "foo", file = "/tmp/test.c", linenr = 10 },
                        },
                    },
                    {
                        count = 20,
                        frames = {
                            { symbol = "bar", file = "/tmp/test.c", linenr = 20 },
                        },
                    },
                    {
                        count = 10,
                        frames = {
                            { symbol = "baz", file = "/tmp/test.c", linenr = 30 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local entries, total_count = find_hottest.hottest_lines_table("cycles")

            assert.are.equal(35, total_count)
            assert.are.equal(3, #entries)
            -- Should be sorted descending by count
            assert.are.equal(20, entries[1].count)
            assert.are.equal(10, entries[2].count)
            assert.are.equal(5, entries[3].count)
        end)

        it("should include correct file, linenr, count in each entry", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.c", linenr = 42 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local entries, _ = find_hottest.hottest_lines_table("cycles")

            assert.are.equal(1, #entries)
            assert.are.equal("/tmp/test.c", entries[1].file)
            assert.are.equal(42, entries[1].linenr)
            assert.are.equal(42, entries[1].linenr_end)
            assert.are.equal(10, entries[1].count)
        end)

        it("should include entries from multiple files", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/main.c", linenr = 10 },
                            { symbol = "helper", file = "/tmp/helper.c", linenr = 20 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local entries, _ = find_hottest.hottest_lines_table("cycles")

            assert.are.equal(2, #entries)
            -- Both should have count 10, order depends on sorting (same count = unstable)
            local files = { entries[1].file, entries[2].file }
            table.sort(files)
            assert.are.same({ "/tmp/helper.c", "/tmp/main.c" }, files)
        end)

        it("should handle symbol entries (unknown file)", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "unknown_func" }, -- no file/linenr
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local entries, _ = find_hottest.hottest_lines_table("cycles")

            assert.are.equal(1, #entries)
            assert.is_nil(entries[1].file)
            assert.are.equal("unknown_func", entries[1].symbol)
            assert.are.equal(10, entries[1].count)
        end)

        it("should filter entries below minimum threshold", function()
            -- Set a higher minimum
            config.values.formats = {
                { percent = false, format = "%d", minimum = 10 },
            }

            local traces = {
                ["cycles"] = {
                    {
                        count = 5,
                        frames = {
                            { symbol = "low", file = "/tmp/test.c", linenr = 10 },
                        },
                    },
                    {
                        count = 15,
                        frames = {
                            { symbol = "high", file = "/tmp/test.c", linenr = 20 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local entries, _ = find_hottest.hottest_lines_table("cycles")

            -- Only the entry with count >= 10 should be included
            assert.are.equal(1, #entries)
            assert.are.equal(15, entries[1].count)
        end)
    end)

    describe("hottest_symbols_table", function()
        it("should return symbol entries sorted by count descending", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 5,
                        frames = {
                            { symbol = "foo", file = "/tmp/test.c", linenr = 10 },
                        },
                    },
                    {
                        count = 20,
                        frames = {
                            { symbol = "bar", file = "/tmp/test.c", linenr = 20 },
                        },
                    },
                    {
                        count = 10,
                        frames = {
                            { symbol = "baz", file = "/tmp/test.c", linenr = 30 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local entries, total_count = find_hottest.hottest_symbols_table("cycles")

            assert.are.equal(35, total_count)
            assert.are.equal(3, #entries)
            -- Should be sorted descending by count
            assert.are.equal(20, entries[1].count)
            assert.are.equal(10, entries[2].count)
            assert.are.equal(5, entries[3].count)
        end)

        it("should include min_line and max_line for symbols", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "foo", file = "/tmp/test.c", linenr = 10 },
                            { symbol = "foo", file = "/tmp/test.c", linenr = 15 },
                            { symbol = "foo", file = "/tmp/test.c", linenr = 20 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local entries, _ = find_hottest.hottest_symbols_table("cycles")

            assert.are.equal(1, #entries)
            assert.are.equal("foo", entries[1].symbol)
            assert.are.equal("/tmp/test.c", entries[1].file)
            assert.are.equal(10, entries[1].linenr) -- min_line
            assert.are.equal(20, entries[1].linenr_end) -- max_line
        end)

        it("should handle unknown symbols (file='symbol')", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "unknown_func" }, -- no file/linenr
                        },
                    },
                    {
                        count = 5,
                        frames = {
                            { symbol = "known_func", file = "/tmp/test.c", linenr = 10 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local entries, _ = find_hottest.hottest_symbols_table("cycles")

            assert.are.equal(2, #entries)
            -- First entry should be unknown_func (higher count)
            assert.are.equal("unknown_func", entries[1].symbol)
            assert.is_nil(entries[1].file)
            assert.is_nil(entries[1].linenr)
            -- Second entry should be known_func
            assert.are.equal("known_func", entries[2].symbol)
            assert.are.equal("/tmp/test.c", entries[2].file)
        end)
    end)

    describe("hottest_callers_table", function()
        it("should return callers for a line range", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.c", linenr = 10 },
                            { symbol = "foo", file = "/tmp/test.c", linenr = 20 },
                        },
                    },
                    {
                        count = 5,
                        frames = {
                            { symbol = "helper", file = "/tmp/test.c", linenr = 30 },
                            { symbol = "foo", file = "/tmp/test.c", linenr = 20 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local entries, total_count = find_hottest.hottest_callers_table("cycles", "/tmp/test.c", 20, 20)

            -- total_count is based on rec_count of lines in range
            assert.are.equal(15, total_count)
            assert.are.equal(2, #entries)
            -- Callers should be sorted by count descending
            assert.are.equal(10, entries[1].count) -- main at line 10
            assert.are.equal(5, entries[2].count) -- helper at line 30
        end)

        it("should handle line range spanning multiple lines", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.c", linenr = 5 },
                            { symbol = "foo", file = "/tmp/test.c", linenr = 20 },
                        },
                    },
                    {
                        count = 5,
                        frames = {
                            { symbol = "main", file = "/tmp/test.c", linenr = 5 },
                            { symbol = "bar", file = "/tmp/test.c", linenr = 25 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            -- Query callers for lines 20-25 (both foo and bar)
            local entries, _ = find_hottest.hottest_callers_table("cycles", "/tmp/test.c", 20, 25)

            assert.are.equal(1, #entries)
            assert.are.equal(15, entries[1].count) -- main called both
            assert.are.equal(5, entries[1].linenr)
        end)

        it("should return nil for file not in callgraph", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.c", linenr = 10 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local entries = find_hottest.hottest_callers_table("cycles", "/tmp/nonexistent.c", 1, 10)

            assert.is_nil(entries)
        end)
    end)

    describe("hottest_callees_table", function()
        it("should return callees for a line range", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.c", linenr = 10 },
                            { symbol = "foo", file = "/tmp/test.c", linenr = 20 },
                        },
                    },
                    {
                        count = 5,
                        frames = {
                            { symbol = "main", file = "/tmp/test.c", linenr = 10 },
                            { symbol = "bar", file = "/tmp/test.c", linenr = 30 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local entries, total_count = find_hottest.hottest_callees_table("cycles", "/tmp/test.c", 10, 10)

            -- total_count is based on rec_count of lines in range
            assert.are.equal(15, total_count)
            assert.are.equal(2, #entries)
            -- Callees should be sorted by count descending
            assert.are.equal(10, entries[1].count) -- foo at line 20
            assert.are.equal(5, entries[2].count) -- bar at line 30
        end)

        it("should return nil for file not in callgraph", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.c", linenr = 10 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local entries = find_hottest.hottest_callees_table("cycles", "/tmp/nonexistent.c", 1, 10)

            assert.is_nil(entries)
        end)

        it("should handle cross-file callees", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/main.c", linenr = 10 },
                            { symbol = "helper", file = "/tmp/helper.c", linenr = 20 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local entries, _ = find_hottest.hottest_callees_table("cycles", "/tmp/main.c", 10, 10)

            assert.are.equal(1, #entries)
            assert.are.equal("/tmp/helper.c", entries[1].file)
            assert.are.equal(20, entries[1].linenr)
            assert.are.equal(10, entries[1].count)
        end)
    end)

    describe("format_entry", function()
        it("should format entry with file and line number", function()
            local entry = {
                symbol = nil,
                file = "/tmp/test.c",
                linenr = 42,
                linenr_end = 42,
                count = 100,
            }

            local result = find_hottest.format_entry(entry, 1000)

            -- Format is "{count} {path}:{linenr}"
            -- With minimum=0 and format="%d", should be "100 /tmp/test.c:42"
            -- (path may be shortened by fnamemodify)
            assert.is_truthy(result:match("^100"))
            assert.is_truthy(result:match(":42$"))
        end)

        it("should format entry with symbol and location", function()
            local entry = {
                symbol = "my_function",
                file = "/tmp/test.c",
                linenr = 10,
                linenr_end = 20,
                count = 50,
            }

            local result = find_hottest.format_entry(entry, 100)

            -- Format is "{count} {symbol} at {path}:{linenr}-{linenr_end}"
            assert.is_truthy(result:match("^50"))
            assert.is_truthy(result:match("my_function"))
            assert.is_truthy(result:match(":10%-20$"))
        end)

        it("should format symbol-only entry (no file)", function()
            local entry = {
                symbol = "unknown_func",
                file = nil,
                linenr = nil,
                linenr_end = nil,
                count = 25,
            }

            local result = find_hottest.format_entry(entry, 100)

            -- Format is "{count} {symbol}"
            assert.are.equal("25 unknown_func", result)
        end)

        it("should format entry with same linenr and linenr_end", function()
            local entry = {
                symbol = "func",
                file = "/tmp/test.c",
                linenr = 15,
                linenr_end = 15,
                count = 30,
            }

            local result = find_hottest.format_entry(entry, 100)

            -- Should show just :15, not :15-15
            assert.is_truthy(result:match(":15$"))
            assert.is_falsy(result:match("15%-15"))
        end)

        it("should format with percentage format", function()
            config.values.formats = {
                { percent = true, format = "%.1f%%", minimum = 0 },
            }

            local entry = {
                symbol = nil,
                file = "/tmp/test.c",
                linenr = 42,
                linenr_end = 42,
                count = 250,
            }

            local result = find_hottest.format_entry(entry, 1000)

            -- 250/1000 = 25%
            assert.is_truthy(result:match("^25.0%%"))
        end)
    end)
end)
