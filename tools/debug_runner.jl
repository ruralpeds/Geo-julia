#!/usr/bin/env julia
# tools/debug_runner.jl
#
# Automated debug cycle for the Geo-Julia open healthcare textbook.
#
# Usage:
#   julia tools/debug_runner.jl                        # run all volumes
#   julia tools/debug_runner.jl --vol 12               # single volume
#   julia tools/debug_runner.jl --vol 10,11,12         # subset
#   julia tools/debug_runner.jl --retries 3            # retry flaky tests
#   julia tools/debug_runner.jl --report debug_out.md  # custom report path
#   julia tools/debug_runner.jl --fast                 # skip integration tests
#
# Exit code:
#   0  all tests passed
#   1  one or more tests failed
#   2  internal runner error

using Test

const REPO_ROOT = abspath(joinpath(@__DIR__, ".."))

# ─── Include shared utilities ─────────────────────────────────────────────────
include(joinpath(REPO_ROOT, "shared", "ErrorHandling", "src", "ErrorHandling.jl"))
include(joinpath(REPO_ROOT, "shared", "TestUtils",     "src", "TestUtils.jl"))
using .ErrorHandling, .TestUtils

# ─── Configuration ────────────────────────────────────────────────────────────

struct RunConfig
    volumes::Vector{Int}
    max_retries::Int
    report_path::String
    skip_integration::Bool
    verbose::Bool
    fail_fast::Bool
end

function parse_args(args::Vector{String})::RunConfig
    volumes       = [10, 11, 12]
    max_retries   = 2
    report_path   = joinpath(REPO_ROOT, "tools", "debug_report.md")
    skip_integ    = false
    verbose       = true
    fail_fast     = false

    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--vol" && i < length(args)
            i += 1
            volumes = parse.(Int, split(args[i], ","))
        elseif a == "--retries" && i < length(args)
            i += 1
            max_retries = parse(Int, args[i])
        elseif a == "--report" && i < length(args)
            i += 1
            report_path = args[i]
        elseif a == "--fast"
            skip_integ = true
        elseif a == "--quiet"
            verbose = false
        elseif a == "--fail-fast"
            fail_fast = true
        end
        i += 1
    end
    RunConfig(volumes, max_retries, report_path, skip_integ, verbose, fail_fast)
end

# ─── Test file discovery ──────────────────────────────────────────────────────

"""
    discover_test_files(cfg) -> Vector{NamedTuple}

Walk the repo tree and return all test files as named tuples with fields
`path`, `vol`, `kind` (:unit | :integration), and `label`.
"""
function discover_test_files(cfg::RunConfig)
    files = NamedTuple[]

    vol_dirs = Dict(
        10 => "vol10_geostatistics_mapping",
        11 => "vol11_causal_inference",
        12 => "vol12_health_optimization",
    )
    shared_dirs = [
        (label="ErrorHandling", path=joinpath(REPO_ROOT, "shared", "ErrorHandling", "test", "runtests.jl")),
        (label="TestUtils",     path=joinpath(REPO_ROOT, "shared", "TestUtils",     "test", "runtests.jl")),
    ]

    # Shared framework tests (always run)
    for sd in shared_dirs
        isfile(sd.path) && push!(files, (
            path  = sd.path,
            vol   = 0,
            kind  = :unit,
            label = "shared/$(sd.label)",
        ))
    end

    for v in cfg.volumes
        haskey(vol_dirs, v) || continue
        vol_root = joinpath(REPO_ROOT, vol_dirs[v])
        isdir(vol_root) || continue

        pkg_dir = joinpath(vol_root, "packages")
        if isdir(pkg_dir)
            for pkg in readdir(pkg_dir; join=true)
                isdir(pkg) || continue
                rt = joinpath(pkg, "test", "runtests.jl")
                isfile(rt) && push!(files, (
                    path  = rt,
                    vol   = v,
                    kind  = :unit,
                    label = "vol$(v)/$(basename(pkg))",
                ))
            end
        end

        if !cfg.skip_integration
            it = joinpath(vol_root, "test", "integration_test.jl")
            isfile(it) && push!(files, (
                path  = it,
                vol   = v,
                kind  = :integration,
                label = "vol$(v)/integration",
            ))
        end
    end
    files
end

# ─── Failure categorisation (extends TestUtils) ───────────────────────────────

function classify_exception(e::Exception)::FailureCategory
    e isa NumericalInstabilityError && return :numerical
    e isa ConvergenceError          && return :convergence
    e isa InfeasibilityError        && return :infeasibility
    e isa DimensionMismatchError    && return :dimension
    e isa InputValidationError      && return :validation
    e isa ConfigurationError        && return :configuration
    # Standard Julia exceptions
    e isa DimensionMismatch         && return :dimension
    e isa DomainError               && return :domain
    e isa OverflowError             && return :numerical
    e isa StackOverflowError        && return :stack_overflow
    msg = sprint(showerror, e)
    categorise_failure(msg)
end

"""
    format_exception(e, bt) -> String

Format an exception with its backtrace into a compact multi-line string.
"""
function format_exception(e::Exception, bt)
    buf = IOBuffer()
    showerror(buf, e, bt; backtrace=true)
    s = String(take!(buf))
    # Truncate very long backtraces
    lines = split(s, '\n')
    length(lines) <= 30 ? s : join(lines[1:30], '\n') * "\n  [backtrace truncated]"
end

# ─── Single-file test runner with capture ─────────────────────────────────────

"""
    run_test_file(entry, cfg) -> TestOutcome

Run the Julia file at `entry.path` in a sandboxed module, capture the
`Test.@testset` results (pass / fail / error counts), time the run,
and return a `TestOutcome`.

If the run throws (e.g., the file cannot be parsed), the outcome records
`errored=1` with the exception message.
"""
function run_test_file(entry::NamedTuple, cfg::RunConfig)::TestOutcome
    label    = entry.label
    fpath    = entry.path
    t0       = time()
    passed   = 0
    failed   = 0
    errored  = 0
    err_msg  = nothing

    cfg.verbose && print("  Running $(label) … ")

    try
        # Isolate includes in a fresh anonymous module to avoid name collisions
        sandbox = Module(Symbol("Sandbox_$(replace(label, '/'=> '_'))"))

        # Redirect stdout/stderr during test run to suppress noise unless verbose
        out_io = cfg.verbose ? stdout : IOBuffer()
        redirect_stdout(out_io) do
            Base.include(sandbox, fpath)
        end

        # Collect results from the test log
        ts = Test.get_testset()
        if ts isa Test.DefaultTestSet
            r  = ts.results
            passed  = count(x -> x isa Test.Pass,   r)
            failed  = count(x -> x isa Test.Fail,   r)
            errored = count(x -> x isa Test.Error,  r)
        end
    catch e
        bt      = catch_backtrace()
        err_msg = format_exception(e, bt)
        errored = 1
        cfg.verbose && println("FAILED")
        cfg.verbose && println("    $(sprint(showerror, e))")
    end

    elapsed = time() - t0
    outcome = TestOutcome(label, fpath, passed, failed, errored, elapsed;
                          msg=err_msg)
    if cfg.verbose
        s = status(outcome)
        if s == :pass
            println("PASS  ($(passed) assertions, $(round(elapsed; digits=2))s)")
        else
            println("FAIL  ($(failed) failed, $(errored) errors, $(round(elapsed; digits=2))s)")
        end
    end
    outcome
end

# ─── Retry logic ─────────────────────────────────────────────────────────────

"""
    run_with_retry(entry, cfg) -> TestOutcome

Run a test file up to `cfg.max_retries` additional times if it fails.
Each retry uses a fresh module scope. Returns the last outcome.
"""
function run_with_retry(entry::NamedTuple, cfg::RunConfig)::TestOutcome
    outcome = run_test_file(entry, cfg)
    retries = 0
    while status(outcome) != :pass && retries < cfg.max_retries
        retries += 1
        cfg.verbose && println("    ↩ Retry $(retries)/$(cfg.max_retries): $(entry.label)")
        sleep(0.1 * 2^(retries - 1))   # exponential back-off: 0.1s, 0.2s, 0.4s
        prev    = outcome
        outcome = run_test_file(entry, cfg)
        # If result is the same failure, record the retry count
        if status(outcome) != :pass
            outcome = TestOutcome(outcome.name, outcome.file,
                                  outcome.passed, outcome.failed,
                                  outcome.errored, outcome.elapsed_s;
                                  msg=outcome.error_msg, retries=retries)
        end
    end
    outcome
end

# ─── Main debug cycle ─────────────────────────────────────────────────────────

"""
    run_debug_cycle(cfg) -> ResultStore

Execute the full debug cycle:
1. Discover test files
2. Run each with retry logic
3. Collect outcomes into a ResultStore
4. Print a live summary table
5. Return the store for report generation

Respects `cfg.fail_fast`: stops after the first failing test group.
"""
function run_debug_cycle(cfg::RunConfig)::ResultStore
    store  = ResultStore()
    files  = discover_test_files(cfg)

    println("\n", "═"^72)
    println("  Geo-Julia Debug Runner  —  $(now_str())")
    println("  Volumes: $(cfg.volumes)  |  Retries: $(cfg.max_retries)  ",
            "|  Skip integration: $(cfg.skip_integration)")
    println("═"^72)

    vol_groups = Dict{Int,Vector{NamedTuple}}()
    for f in files
        push!(get!(vol_groups, f.vol, NamedTuple[]), f)
    end

    for v in sort(collect(keys(vol_groups)))
        gname = v == 0 ? "shared framework" : "Vol $(v)"
        println("\n── $(gname) ──────────────────────────────────────────────")

        for entry in vol_groups[v]
            outcome = run_with_retry(entry, cfg)
            push!(store, outcome)

            if cfg.fail_fast && status(outcome) == :fail
                println("\n⚑ FAIL-FAST triggered — stopping after: $(entry.label)")
                return store
            end
        end
    end

    println()
    print_live_summary(store)
    store
end

# ─── Console summary ──────────────────────────────────────────────────────────

function print_live_summary(store::ResultStore)
    s = summary(store)
    println("═"^72)
    @printf "  Results: %d passed / %d failed / %d total  (%.0f%% pass rate)\n" \
        s.passed s.failed s.total (s.pass_rate * 100)
    @printf "  Assertions: %d run, %d failed\n" s.total_assertions s.total_failures
    @printf "  Wall time: %.1f s\n" s.elapsed_s

    fails = failed_outcomes(store)
    if !isempty(fails)
        println("\n  FAILED tests:")
        for o in fails
            cat = categorise_outcome(o)
            @printf "    ✗ %-40s  [%s]\n" o.name cat
            if !isnothing(o.error_msg)
                # Print first 3 lines of error message
                lines = split(o.error_msg, '\n')[1:min(3, end)]
                for l in lines
                    println("        ", l)
                end
            end
        end
    else
        println("\n  ✓ All tests passed.")
    end
    println("═"^72)
end

# ─── Report generation (delegates to test_reporter.jl) ───────────────────────

function write_report(store::ResultStore, cfg::RunConfig)
    reporter_path = joinpath(REPO_ROOT, "tools", "test_reporter.jl")
    if isfile(reporter_path)
        include(reporter_path)
        write_debug_report(store, cfg.report_path)
        println("\n  Report written to: $(cfg.report_path)")
    end
end

# ─── Utility ──────────────────────────────────────────────────────────────────

using Printf, Dates

now_str() = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")

# ─── Entry point ──────────────────────────────────────────────────────────────

function main(args::Vector{String}=ARGS)
    cfg   = parse_args(args)
    store = run_debug_cycle(cfg)
    write_report(store, cfg)

    n_fail = summary(store).failed
    exit(n_fail > 0 ? 1 : 0)
end

# Run when executed as a script (not when included)
if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
