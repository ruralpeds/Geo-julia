#!/usr/bin/env julia
# tools/test_reporter.jl
#
# Structured Markdown report generator for the debug_runner.
# Can also be run standalone:
#
#   julia tools/test_reporter.jl path/to/store_snapshot.jl
#
# The primary entry point is `write_debug_report(store, path)`.

using Printf, Dates

# Ensure TestUtils types are available
if !isdefined(Main, :TestUtils)
    include(joinpath(dirname(@__DIR__), "shared", "TestUtils", "src", "TestUtils.jl"))
    using .TestUtils
end
if !isdefined(Main, :ErrorHandling)
    include(joinpath(dirname(@__DIR__), "shared", "ErrorHandling", "src", "ErrorHandling.jl"))
    using .ErrorHandling
end

# ─── Helpers ─────────────────────────────────────────────────────────────────

_badge(s::Symbol) = s == :pass ? "✅" : "❌"
_cat_label = Dict(
    :numerical     => "Numerical instability",
    :convergence   => "Convergence failure",
    :dimension     => "Dimension mismatch",
    :infeasibility => "Infeasible problem",
    :validation    => "Input validation",
    :configuration => "Bad configuration",
    :assertion     => "Assertion failure",
    :approximation => "Tolerance exceeded",
    :exception     => "Unexpected exception",
    :domain        => "Domain error",
    :stack_overflow => "Stack overflow",
    :unknown       => "Unknown",
)

_cat_suggestion = Dict(
    :numerical     => "Check for NaN/Inf inputs; add `check_finite()` guard; consider `regularize!()`.",
    :convergence   => "Increase `max_iter`; tighten initialisation; verify learning-rate schedule.",
    :dimension     => "Confirm array shapes before calling; use `check_2d_coords()` / `check_conformable()`.",
    :infeasibility => "Loosen constraints; verify demand/capacity ratio; check `coverage_radius`.",
    :validation    => "Validate inputs at function entry with `check_positive()` / `check_weights()`.",
    :configuration => "Check keyword argument ranges (p ≤ m, 0 ≤ γ < 1, etc.).",
    :assertion     => "Review the failing `@test` expression and its expected value.",
    :approximation => "Widen `atol`/`rtol` or improve algorithm accuracy.",
    :exception     => "Inspect the full stack trace; add a try/catch or input guard.",
    :domain        => "Guard log/sqrt/etc. with domain checks (`safe_log`, `safe_sqrt`).",
    :stack_overflow => "Reduce recursion depth or convert to iterative algorithm.",
    :unknown       => "Inspect the error message manually.",
)

# ─── Report sections ─────────────────────────────────────────────────────────

function _header(io::IO, store::ResultStore)
    s = summary(store)
    ts = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
    println(io, "# Geo-Julia Debug Report\n")
    println(io, "> Generated: $(ts)\n")
    println(io, "## Executive Summary\n")
    println(io, "| Metric | Value |")
    println(io, "|--------|-------|")
    @printf io "| Test suites run   | %d |\n"   s.total
    @printf io "| Passed            | %d |\n"   s.passed
    @printf io "| Failed            | %d |\n"   s.failed
    @printf io "| Pass rate         | %.1f%% |\n" (s.pass_rate * 100)
    @printf io "| Total assertions  | %d |\n"   s.total_assertions
    @printf io "| Failed assertions | %d |\n"   s.total_failures
    @printf io "| Wall time         | %.1f s |\n" s.elapsed_s
    isnothing(s.slowest) || @printf io "| Slowest suite     | `%s` |\n" s.slowest
    println(io)
end

function _pass_table(io::IO, store::ResultStore)
    passes = passed_outcomes(store)
    isempty(passes) && return
    println(io, "## Passed Suites ($(length(passes)))\n")
    println(io, "| Suite | Assertions | Time (s) |")
    println(io, "|-------|-----------|----------|")
    for o in sort(passes; by=o->o.name)
        @printf io "| %-38s | %9d | %8.2f |\n" "`$(o.name)`" o.passed o.elapsed_s
    end
    println(io)
end

function _fail_table(io::IO, store::ResultStore)
    fails = failed_outcomes(store)
    isempty(fails) && return
    println(io, "## Failed Suites ($(length(fails)))\n")

    # Group by failure category
    by_cat = Dict{FailureCategory, Vector{TestOutcome}}()
    for o in fails
        cat = categorise_outcome(o)
        push!(get!(by_cat, cat, TestOutcome[]), o)
    end

    for (cat, outcomes) in sort(collect(by_cat); by=kv->string(kv[1]))
        label = get(_cat_label, cat, string(cat))
        sugg  = get(_cat_suggestion, cat, "")
        println(io, "### $(label) (`$(cat)`)\n")
        println(io, "> **Suggested fix**: $(sugg)\n")
        println(io, "| Suite | Failed | Errored | Retries | Time (s) |")
        println(io, "|-------|--------|---------|---------|----------|")
        for o in sort(outcomes; by=o->o.name)
            @printf io "| %-38s | %6d | %7d | %7d | %8.2f |\n" \
                "`$(o.name)`" o.failed o.errored o.retries o.elapsed_s
        end
        println(io)

        # Error messages
        for o in outcomes
            isnothing(o.error_msg) && continue
            println(io, "<details>")
            println(io, "<summary><code>$(o.name)</code> — error output</summary>\n")
            println(io, "```")
            # Print at most 40 lines
            lines = split(o.error_msg, '\n')
            println(io, join(lines[1:min(40, end)], '\n'))
            length(lines) > 40 && println(io, "… ($(length(lines)-40) lines truncated)")
            println(io, "```\n")
            println(io, "</details>\n")
        end
    end
end

function _failure_category_pie(io::IO, store::ResultStore)
    fails = failed_outcomes(store)
    isempty(fails) && return
    println(io, "## Failure Category Breakdown\n")
    counts = Dict{FailureCategory,Int}()
    for o in fails
        cat = categorise_outcome(o)
        counts[cat] = get(counts, cat, 0) + 1
    end
    println(io, "| Category | Count | Proportion |")
    println(io, "|----------|-------|------------|")
    total = sum(values(counts))
    for (cat, n) in sort(collect(counts); by=kv->-kv[2])
        label = get(_cat_label, cat, string(cat))
        @printf io "| %-25s | %5d | %9.1f%% |\n" label n (100.0*n/total)
    end
    println(io)
end

function _debug_checklist(io::IO, store::ResultStore)
    fails = failed_outcomes(store)
    isempty(fails) && return
    println(io, "## Debug Checklist\n")
    println(io, "Work through each item in order before re-running the cycle:\n")
    cats = unique(categorise_outcome(o) for o in fails)
    step = 1
    for cat in cats
        sugg = get(_cat_suggestion, cat, "")
        label = get(_cat_label, cat, string(cat))
        println(io, "$(step). **$(label)**: $(sugg)")
        step += 1
    end
    println(io)
    println(io, "After applying fixes, re-run:\n")
    println(io, "```bash")
    println(io, "julia tools/debug_runner.jl --retries 2")
    println(io, "```\n")
end

function _footer(io::IO)
    println(io, "---")
    println(io, "_Report generated by `tools/debug_runner.jl` · Geo-Julia Healthcare Textbook_")
end

# ─── Public API ───────────────────────────────────────────────────────────────

"""
    write_debug_report(store, path) -> nothing

Write a Markdown debug report for `store` to `path`.
"""
function write_debug_report(store::ResultStore, path::String)
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        _header(io, store)
        _pass_table(io, store)
        _fail_table(io, store)
        _failure_category_pie(io, store)
        _debug_checklist(io, store)
        _footer(io)
    end
end

"""
    print_debug_report(store) -> nothing

Print a Markdown debug report to stdout.
"""
function print_debug_report(store::ResultStore)
    _header(stdout, store)
    _pass_table(stdout, store)
    _fail_table(stdout, store)
    _failure_category_pie(stdout, store)
    _debug_checklist(stdout, store)
    _footer(stdout)
end

# Standalone use
if abspath(PROGRAM_FILE) == @__FILE__
    println("test_reporter: standalone mode — no store available without debug_runner.")
    println("Use: julia tools/debug_runner.jl --report <path>")
end
