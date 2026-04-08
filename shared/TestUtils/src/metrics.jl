# metrics.jl — Test result collection, summarisation, and regression detection
#
# Provides a lightweight in-process result store that the debug_runner uses
# to aggregate outcomes across many @testset runs.

using Test, Statistics

# ─── Result types ─────────────────────────────────────────────────────────────

"""
    TestOutcome

Records the result of a single named test run.

Fields:
- `name`      — test or testset name
- `file`      — source file path
- `passed`    — number of passing assertions
- `failed`    — number of failing assertions
- `errored`   — number of assertions that threw unexpected errors
- `elapsed_s` — wall-clock time in seconds
- `error_msg` — captured error message if the whole testset threw
- `retries`   — how many retry attempts were needed (0 = first try)
"""
struct TestOutcome
    name::String
    file::String
    passed::Int
    failed::Int
    errored::Int
    elapsed_s::Float64
    error_msg::Union{String,Nothing}
    retries::Int
end

TestOutcome(name, file, passed, failed, errored, elapsed; msg=nothing, retries=0) =
    TestOutcome(name, file, passed, failed, errored, elapsed, msg, retries)

status(o::TestOutcome) =
    o.failed == 0 && o.errored == 0 && isnothing(o.error_msg) ? :pass : :fail

# ─── Result store ─────────────────────────────────────────────────────────────

"""
    ResultStore

Accumulates `TestOutcome`s during a debug run. Thread-unsafe by design
(the debug runner is single-threaded).
"""
mutable struct ResultStore
    outcomes::Vector{TestOutcome}
    start_time::Float64
end

ResultStore() = ResultStore(TestOutcome[], time())

"""
    push!(store, outcome)

Append a `TestOutcome` to the store.
"""
Base.push!(s::ResultStore, o::TestOutcome) = push!(s.outcomes, o)

# ─── Aggregate metrics ────────────────────────────────────────────────────────

"""
    summary(store) -> NamedTuple

Return aggregate statistics for all outcomes in the store.
"""
function summary(store::ResultStore)
    os = store.outcomes
    isempty(os) && return (
        total=0, passed=0, failed=0, pass_rate=NaN,
        total_assertions=0, total_failures=0,
        elapsed_s=0.0, slowest=nothing, fastest=nothing
    )

    passed = count(o -> status(o) == :pass, os)
    failed = length(os) - passed
    t_ass  = sum(o.passed + o.failed for o in os)
    t_fail = sum(o.failed + o.errored for o in os)
    elapsed = time() - store.start_time

    sorted  = sort(os; by=o->o.elapsed_s, rev=true)

    (
        total            = length(os),
        passed           = passed,
        failed           = failed,
        pass_rate        = passed / length(os),
        total_assertions = t_ass,
        total_failures   = t_fail,
        elapsed_s        = elapsed,
        slowest          = isempty(sorted) ? nothing : sorted[1].name,
        fastest          = isempty(sorted) ? nothing : sorted[end].name,
    )
end

"""
    failed_outcomes(store) -> Vector{TestOutcome}

Return only the outcomes that had at least one failure or error.
"""
failed_outcomes(store::ResultStore) = filter(o -> status(o) == :fail, store.outcomes)

"""
    passed_outcomes(store) -> Vector{TestOutcome}

Return only the outcomes where all assertions passed.
"""
passed_outcomes(store::ResultStore) = filter(o -> status(o) == :pass, store.outcomes)

# ─── Failure categorisation ───────────────────────────────────────────────────

"""
    FailureCategory

Enum-like symbol describing why a test failed.

| Symbol | Meaning |
|--------|---------|
| `:assertion`    | `@test expr` was false |
| `:approximation`| `@test a ≈ b atol=…` tolerance exceeded |
| `:exception`    | test threw an unexpected exception |
| `:dimension`    | dimension/shape mismatch |
| `:numerical`    | NaN/Inf in output |
| `:convergence`  | iterative algorithm did not converge |
| `:infeasibility`| optimisation problem returned infeasible |
| `:timeout`      | test exceeded time budget (not enforced in base Julia) |
| `:unknown`      | could not classify |
"""
const FailureCategory = Symbol

"""
    categorise_failure(msg::String) -> FailureCategory

Heuristically classify a failure by scanning the error message string.
"""
function categorise_failure(msg::String)::FailureCategory
    m = lowercase(msg)
    occursin("nan", m) || occursin("inf", m)         && return :numerical
    occursin("converge", m)                            && return :convergence
    occursin("dimension", m) || occursin("shape", m)  && return :dimension
    occursin("infeasible", m) || occursin("feasib", m) && return :infeasibility
    occursin("≈") || occursin("atol") || occursin("rtol") && return :approximation
    occursin("exception") || occursin("error:")        && return :exception
    occursin("false")                                  && return :assertion
    :unknown
end

"""
    categorise_outcome(o::TestOutcome) -> FailureCategory

Classify a failed `TestOutcome`.
"""
function categorise_outcome(o::TestOutcome)::FailureCategory
    status(o) == :pass && return :pass
    isnothing(o.error_msg) ? :assertion : categorise_failure(o.error_msg)
end

# ─── Regression detection ─────────────────────────────────────────────────────

"""
    detect_regressions(current::ResultStore, baseline::ResultStore) -> Vector{String}

Compare two result stores and return names of tests that were passing in
`baseline` but are now failing in `current` (regressions).
"""
function detect_regressions(current::ResultStore, baseline::ResultStore)
    base_pass = Set(o.name for o in passed_outcomes(baseline))
    curr_fail = Set(o.name for o in failed_outcomes(current))
    sort(collect(intersect(base_pass, curr_fail)))
end

# ─── Timing helpers ───────────────────────────────────────────────────────────

"""
    @timed_testset name expr -> (elapsed_s, ts_result)

Run `@testset name expr` and measure wall-clock time.
Returns `(elapsed_seconds, Test.DefaultTestSet)`.
"""
macro timed_testset(name, expr)
    quote
        t0 = time()
        ts = @testset $(esc(name)) $(esc(expr))
        (time() - t0, ts)
    end
end
