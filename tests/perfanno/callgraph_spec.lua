local callgraph = require("perfanno.callgraph")

describe("callgraph", function()
    before_each(function()
        -- Reset state before each test
        callgraph.callgraphs = nil
        callgraph.events = nil
    end)

    describe("load_traces", function()
        it("should process a simple trace with correct counts", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.c", linenr = 10 },
                            { symbol = "foo", file = "/tmp/test.c", linenr = 20 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            assert.is_true(callgraph.is_loaded())
            assert.are.same({ "cycles" }, callgraph.events)

            local cg = callgraph.callgraphs["cycles"]
            assert.equals(10, cg.total_count)
            assert.equals(10, cg.max_count)

            -- Both lines should have count 10
            assert.equals(10, cg.node_info["/tmp/test.c"][10].count)
            assert.equals(10, cg.node_info["/tmp/test.c"][20].count)
        end)

        it("should aggregate counts from multiple traces", function()
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

            local cg = callgraph.callgraphs["cycles"]
            assert.equals(15, cg.total_count)
            assert.equals(15, cg.max_count)

            -- Line 10 should have count 15 (appears in both traces)
            assert.equals(15, cg.node_info["/tmp/test.c"][10].count)
            -- Line 20 should have count 10 (only in first trace)
            assert.equals(10, cg.node_info["/tmp/test.c"][20].count)
            -- Line 30 should have count 5 (only in second trace)
            assert.equals(5, cg.node_info["/tmp/test.c"][30].count)
        end)

        it("should track rec_count separately from count for recursive calls", function()
            -- Simulate a recursive call: main -> foo -> foo (recursive)
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.c", linenr = 10 },
                            { symbol = "foo", file = "/tmp/test.c", linenr = 20 },
                            { symbol = "foo", file = "/tmp/test.c", linenr = 20 }, -- recursive call
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local cg = callgraph.callgraphs["cycles"]

            -- count should only be 10 (counted once per trace regardless of recursion)
            assert.equals(10, cg.node_info["/tmp/test.c"][20].count)
            -- rec_count should be 20 (counted for each frame in the trace)
            assert.equals(20, cg.node_info["/tmp/test.c"][20].rec_count)
        end)

        it("should populate out_counts for caller relationships", function()
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

            local cg = callgraph.callgraphs["cycles"]

            -- Line 10 (main) should have out_counts to lines 20 and 30
            assert.equals(10, cg.node_info["/tmp/test.c"][10].out_counts["/tmp/test.c"][20])
            assert.equals(5, cg.node_info["/tmp/test.c"][10].out_counts["/tmp/test.c"][30])
        end)

        it("should populate in_counts for callee relationships", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.c", linenr = 10 },
                            { symbol = "foo", file = "/tmp/test.c", linenr = 20 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local cg = callgraph.callgraphs["cycles"]

            -- Line 20 (foo) should have in_counts from line 10 (main)
            assert.equals(10, cg.node_info["/tmp/test.c"][20].in_counts["/tmp/test.c"][10])
        end)

        it("should handle multiple events separately", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.c", linenr = 10 },
                        },
                    },
                },
                ["cache-misses"] = {
                    {
                        count = 5,
                        frames = {
                            { symbol = "main", file = "/tmp/test.c", linenr = 10 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            assert.is_true(callgraph.is_loaded())
            assert.equals(2, #callgraph.events)

            -- Each event should have its own callgraph
            assert.equals(10, callgraph.callgraphs["cycles"].total_count)
            assert.equals(5, callgraph.callgraphs["cache-misses"].total_count)
        end)

        it("should track symbol information", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.c", linenr = 10 },
                            { symbol = "foo", file = "/tmp/test.c", linenr = 20 },
                            { symbol = "foo", file = "/tmp/test.c", linenr = 25 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local cg = callgraph.callgraphs["cycles"]

            -- Check that symbols are tracked
            assert.equals(10, cg.symbols["/tmp/test.c"]["main"].count)
            assert.equals(10, cg.symbols["/tmp/test.c"]["foo"].count)

            -- Check that min_line is tracked (foo appears at lines 20 and 25)
            assert.equals(20, cg.symbols["/tmp/test.c"]["foo"].min_line)
        end)

        it("should handle frames across multiple files", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/main.c", linenr = 10 },
                            { symbol = "helper", file = "/tmp/helper.c", linenr = 5 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local cg = callgraph.callgraphs["cycles"]

            -- Both files should have entries
            assert.equals(10, cg.node_info["/tmp/main.c"][10].count)
            assert.equals(10, cg.node_info["/tmp/helper.c"][5].count)

            -- Cross-file edges should work
            assert.equals(10, cg.node_info["/tmp/main.c"][10].out_counts["/tmp/helper.c"][5])
            assert.equals(10, cg.node_info["/tmp/helper.c"][5].in_counts["/tmp/main.c"][10])
        end)

        it("should handle frames without file/linenr as symbols", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.c", linenr = 10 },
                            { symbol = "unknown_func" }, -- no file/linenr
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            local cg = callgraph.callgraphs["cycles"]

            -- The known frame should still be processed
            assert.equals(10, cg.node_info["/tmp/test.c"][10].count)

            -- Unknown frames go to node_info["symbol"]
            assert.equals(10, cg.node_info["symbol"]["unknown_func"].count)
        end)
    end)

    describe("is_loaded", function()
        it("should return false when no callgraph is loaded", function()
            assert.is_false(callgraph.is_loaded())
        end)

        it("should return true after loading traces", function()
            callgraph.load_traces({
                ["cycles"] = {
                    { count = 1, frames = { { symbol = "main", file = "/tmp/test.c", linenr = 1 } } },
                },
            })
            assert.is_true(callgraph.is_loaded())
        end)
    end)

    describe("check_event", function()
        it("should not error for valid event", function()
            callgraph.load_traces({
                ["cycles"] = {
                    { count = 1, frames = { { symbol = "main", file = "/tmp/test.c", linenr = 1 } } },
                },
            })
            assert.has_no.errors(function()
                callgraph.check_event("cycles")
            end)
        end)

        it("should error for invalid event", function()
            callgraph.load_traces({
                ["cycles"] = {
                    { count = 1, frames = { { symbol = "main", file = "/tmp/test.c", linenr = 1 } } },
                },
            })
            assert.has.errors(function()
                callgraph.check_event("invalid")
            end)
        end)
    end)

    describe("merge_in_counts", function()
        it("should merge in_counts from multiple nodes", function()
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

            -- Merge in_counts for both foo and bar
            local merged = callgraph.merge_in_counts("cycles", {
                { "/tmp/test.c", 20 },
                { "/tmp/test.c", 30 },
            })

            -- Both are called from line 10, so merged should show 15 calls from line 10
            assert.equals(15, merged["/tmp/test.c"][10])
        end)
    end)

    describe("merge_out_counts", function()
        it("should merge out_counts from multiple nodes", function()
            local traces = {
                ["cycles"] = {
                    {
                        count = 10,
                        frames = {
                            { symbol = "main", file = "/tmp/test.c", linenr = 10 },
                            { symbol = "foo", file = "/tmp/test.c", linenr = 20 },
                            { symbol = "baz", file = "/tmp/test.c", linenr = 40 },
                        },
                    },
                    {
                        count = 5,
                        frames = {
                            { symbol = "main", file = "/tmp/test.c", linenr = 10 },
                            { symbol = "bar", file = "/tmp/test.c", linenr = 30 },
                            { symbol = "baz", file = "/tmp/test.c", linenr = 40 },
                        },
                    },
                },
            }

            callgraph.load_traces(traces)

            -- Merge out_counts for main (line 10)
            local merged = callgraph.merge_out_counts("cycles", {
                { "/tmp/test.c", 10 },
            })

            -- main calls foo (10) and bar (5)
            assert.equals(10, merged["/tmp/test.c"][20])
            assert.equals(5, merged["/tmp/test.c"][30])
        end)
    end)
end)
