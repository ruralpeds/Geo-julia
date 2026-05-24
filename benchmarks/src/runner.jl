#=
Geo-Julia Benchmark Runner
===========================
Runs all benchmark suites and produces a JSON report with timings,
memory allocations, and regression detection against a baseline.

Usage:
    julia --project=benchmarks benchmarks/src/runner.jl              # run all
    julia --project=benchmarks benchmarks/src/runner.jl geostat      # run one suite
    julia --project=benchmarks benchmarks/src/runner.jl --save       # save as baseline
    julia --project=benchmarks benchmarks/src/runner.jl --compare    # compare to baseline
=#

using BenchmarkTools, Statistics, Dates, Random, Printf
using JSON3

const BASELINE_PATH = joinpath(@__DIR__, "..", "results", "baseline.json")
const RESULTS_DIR = joinpath(@__DIR__, "..", "results")

BenchmarkTools.DEFAULT_PARAMETERS.samples = 10
BenchmarkTools.DEFAULT_PARAMETERS.seconds = 30
BenchmarkTools.DEFAULT_PARAMETERS.evals = 1

struct BenchmarkEntry
    name::String
    suite::String
    median_ns::Float64
    mean_ns::Float64
    min_ns::Float64
    max_ns::Float64
    memory_bytes::Int
    allocs::Int
    n_input::Int
end

function entry_from_trial(name::String, suite::String, trial::BenchmarkTools.Trial, n::Int)
    BenchmarkEntry(
        name, suite,
        median(trial).time,
        mean(trial).time,
        minimum(trial).time,
        maximum(trial).time,
        trial.memory,
        trial.allocs,
        n,
    )
end

function format_time(ns::Float64)
    if ns < 1_000
        @sprintf("%.1f ns", ns)
    elseif ns < 1_000_000
        @sprintf("%.1f μs", ns / 1_000)
    elseif ns < 1_000_000_000
        @sprintf("%.2f ms", ns / 1_000_000)
    else
        @sprintf("%.3f s", ns / 1_000_000_000)
    end
end

function format_memory(bytes::Int)
    if bytes < 1024
        "$bytes B"
    elseif bytes < 1024^2
        @sprintf("%.1f KiB", bytes / 1024)
    elseif bytes < 1024^3
        @sprintf("%.1f MiB", bytes / 1024^2)
    else
        @sprintf("%.2f GiB", bytes / 1024^3)
    end
end

function print_entry(e::BenchmarkEntry)
    @printf("  %-45s  %12s  %12s  %6d allocs  n=%d\n",
            e.name, format_time(e.median_ns), format_memory(e.memory_bytes), e.allocs, e.n_input)
end

function save_results(entries::Vector{BenchmarkEntry}, path::String)
    mkpath(dirname(path))
    data = Dict(
        "timestamp" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"),
        "julia_version" => string(VERSION),
        "entries" => [Dict(
            "name" => e.name, "suite" => e.suite,
            "median_ns" => e.median_ns, "mean_ns" => e.mean_ns,
            "min_ns" => e.min_ns, "max_ns" => e.max_ns,
            "memory_bytes" => e.memory_bytes, "allocs" => e.allocs,
            "n_input" => e.n_input,
        ) for e in entries],
    )
    open(path, "w") do io
        JSON3.pretty(io, data)
    end
    println("\nResults saved to $path")
end

function compare_to_baseline(entries::Vector{BenchmarkEntry})
    if !isfile(BASELINE_PATH)
        println("\n⚠  No baseline found at $BASELINE_PATH — run with --save first")
        return false
    end
    baseline = JSON3.read(read(BASELINE_PATH, String))
    baseline_map = Dict(e.name => e for e in baseline.entries)

    println("\n" * "=" ^ 90)
    println("  REGRESSION CHECK vs baseline ($(baseline.timestamp))")
    println("=" ^ 90)
    @printf("  %-40s  %12s  %12s  %8s  %s\n", "Benchmark", "Baseline", "Current", "Change", "Status")
    println("  " * "-" ^ 86)

    regressions = 0
    for e in entries
        if !haskey(baseline_map, e.name)
            @printf("  %-40s  %12s  %12s  %8s  %s\n", e.name, "—", format_time(e.median_ns), "NEW", "●")
            continue
        end
        b = baseline_map[e.name]
        ratio = e.median_ns / b.median_ns
        pct = (ratio - 1.0) * 100
        status = if ratio > 1.20
            regressions += 1
            "🔴 REGRESSION"
        elseif ratio > 1.05
            "🟡 slower"
        elseif ratio < 0.80
            "🟢 FASTER"
        elseif ratio < 0.95
            "🟢 faster"
        else
            "⚪ same"
        end
        @printf("  %-40s  %12s  %12s  %+7.1f%%  %s\n",
                e.name, format_time(b.median_ns), format_time(e.median_ns), pct, status)
    end

    if regressions > 0
        println("\n⚠  $regressions regression(s) detected (>20% slower than baseline)")
        return false
    else
        println("\n✓  No regressions detected")
        return true
    end
end

# ──────────────────────────────────────────────────────────────────────
# Suite loaders
# ──────────────────────────────────────────────────────────────────────

function bench_geostat(rng)
    using GeostatHealth
    entries = BenchmarkEntry[]
    println("\n▶ Geostatistics (Vol 10 — GeostatHealth)")

    for n in [50, 200, 500]
        coords = rand(rng, n, 2) .* 100
        z = [sin(coords[i,1]/20) + cos(coords[i,2]/15) + randn(rng)*0.1 for i in 1:n]
        ev = empirical_variogram(coords, z; n_lags=12)
        vm = fit_variogram(ev; model=:spherical)

        t = @benchmark empirical_variogram($coords, $z; n_lags=12)
        push!(entries, entry_from_trial("variogram/empirical (n=$n)", "geostat", t, n))

        t = @benchmark fit_variogram($ev; model=:spherical)
        push!(entries, entry_from_trial("variogram/fit_spherical (n=$n)", "geostat", t, n))

        t = @benchmark ordinary_kriging($z, $coords, $vm)
        push!(entries, entry_from_trial("kriging/ordinary_fit (n=$n)", "geostat", t, n))

        ok = ordinary_kriging(z, coords, vm)
        new_pts = rand(rng, 20, 2) .* 100
        t = @benchmark ok_predict($ok, $new_pts)
        push!(entries, entry_from_trial("kriging/ok_predict (n=$n, m=20)", "geostat", t, n))
    end

    # LOO-CV (expensive, only small n)
    coords_sm = rand(rng, 30, 2) .* 100
    z_sm = randn(rng, 30)
    ev_sm = empirical_variogram(coords_sm, z_sm; n_lags=8)
    vm_sm = fit_variogram(ev_sm; model=:spherical)
    t = @benchmark kriging_loo_cv($z_sm, $coords_sm, $vm_sm)
    push!(entries, entry_from_trial("kriging/loo_cv (n=30)", "geostat", t, 30))

    foreach(print_entry, entries)
    entries
end

function bench_point_patterns(rng)
    using PointPatterns
    entries = BenchmarkEntry[]
    println("\n▶ Point Patterns (Vol 10 — PointPatterns)")

    for n in [100, 500, 1000]
        pts = rand(rng, n, 2) .* 100
        area = 100.0 * 100.0

        t = @benchmark kde2d($pts; n_grid=25)
        push!(entries, entry_from_trial("kde2d (n=$n, grid=25)", "point_patterns", t, n))

        t = @benchmark ripley_k($pts, $area; n_r=15, n_sim=19, rng=$rng)
        push!(entries, entry_from_trial("ripley_k (n=$n, sim=19)", "point_patterns", t, n))

        t = @benchmark dbscan($pts; eps=8.0, min_pts=3)
        push!(entries, entry_from_trial("dbscan (n=$n)", "point_patterns", t, n))
    end

    foreach(print_entry, entries)
    entries
end

function bench_epidemic(rng)
    using InfectiousDisease
    entries = BenchmarkEntry[]
    println("\n▶ Epidemic Models (Vol 13 — InfectiousDisease)")

    for N in [100_000, 1_000_000]
        t = @benchmark sir($N, 10, 0.35, 0.12; t_end=300.0, dt=1.0)
        push!(entries, entry_from_trial("sir (N=$(N÷1000)k)", "epidemic", t, N))

        t = @benchmark seir($N, 5, 10, 0.35, 0.2, 0.12; t_end=300.0, dt=1.0)
        push!(entries, entry_from_trial("seir (N=$(N÷1000)k)", "epidemic", t, N))

        t = @benchmark sir_stochastic($N, 10, 0.35, 0.12; t_end=300.0, dt=1.0, rng=$rng)
        push!(entries, entry_from_trial("sir_stochastic (N=$(N÷1000)k)", "epidemic", t, N))
    end

    # Spatial SIR
    for n_patches in [10, 50]
        pops = fill(10_000, n_patches)
        I0 = zeros(Int, n_patches); I0[1] = 5
        coords = rand(rng, n_patches, 2) .* 200
        t = @benchmark spatial_sir($pops, $I0, $coords, 0.35, 0.12;
                                   coupling_strength=0.01, t_end=200.0, dt=1.0, rng=$rng)
        push!(entries, entry_from_trial("spatial_sir (patches=$n_patches)", "epidemic", t, n_patches))
    end

    foreach(print_entry, entries)
    entries
end

function bench_surveillance(rng)
    using SurveillanceSystems
    entries = BenchmarkEntry[]
    println("\n▶ Surveillance (Vol 13 — SurveillanceSystems)")

    for n in [365, 1825, 3650]
        cases = 10.0 .+ randn(rng, n) .* 3.0
        cases = max.(cases, 0.0)

        t = @benchmark cusum($cases; μ₀=10.0, σ₀=3.0, k=1.0, h=5.0)
        push!(entries, entry_from_trial("cusum (n=$n)", "surveillance", t, n))

        t = @benchmark ewma($cases; λ=0.2, L=2.7, μ₀=10.0, σ₀=3.0)
        push!(entries, entry_from_trial("ewma (n=$n)", "surveillance", t, n))

        t = @benchmark farrington($cases; baseline_window=90, threshold_factor=2.0)
        push!(entries, entry_from_trial("farrington (n=$n)", "surveillance", t, n))
    end

    foreach(print_entry, entries)
    entries
end

function bench_time_series(rng)
    using TimeSeriesHealth
    entries = BenchmarkEntry[]
    println("\n▶ Time Series (Vol 9 — TimeSeriesHealth)")

    for n in [100, 500, 2000]
        y = cumsum(randn(rng, n)) .+ 50.0

        t = @benchmark arima_fit($y, 2, 1, 1)
        push!(entries, entry_from_trial("arima_fit(2,1,1) (n=$n)", "time_series", t, n))

        t = @benchmark kalman_filter($y, 1.0, 0.1)
        push!(entries, entry_from_trial("kalman_filter (n=$n)", "time_series", t, n))

        t = @benchmark auto_arima($y; max_p=3, max_q=3)
        push!(entries, entry_from_trial("auto_arima (n=$n)", "time_series", t, n))
    end

    # DLM fit (EM iterations)
    y_short = cumsum(randn(rng, 200)) .+ 50.0
    t = @benchmark dlm_fit($y_short; max_iter=50)
    push!(entries, entry_from_trial("dlm_fit/EM (n=200, iter=50)", "time_series", t, 200))

    foreach(print_entry, entries)
    entries
end

function bench_survival(rng)
    using SurvivalAnalysis
    entries = BenchmarkEntry[]
    println("\n▶ Survival Analysis (Vol 9 — SurvivalAnalysis)")

    for n in [100, 500, 2000]
        times = sort(rand(rng, n) .* 100)
        status = rand(rng, [0, 1], n)
        X = randn(rng, n, 5)

        t = @benchmark kaplan_meier($times, $status)
        push!(entries, entry_from_trial("kaplan_meier (n=$n)", "survival", t, n))

        t = @benchmark cox_fit($times, $status, $X)
        push!(entries, entry_from_trial("cox_fit (n=$n, p=5)", "survival", t, n))

        t = @benchmark logrank_test($times, $status, rand($rng, [0,1], $n))
        push!(entries, entry_from_trial("logrank_test (n=$n)", "survival", t, n))
    end

    foreach(print_entry, entries)
    entries
end

function bench_spatial_regression(rng)
    using SpatialRegression
    entries = BenchmarkEntry[]
    println("\n▶ Spatial Regression (Vol 8 — SpatialRegression)")

    for n in [50, 150, 400]
        coords = rand(rng, n, 2) .* 100
        X = randn(rng, n, 3)
        y = X * [2.0, -1.0, 0.5] .+ [sin(coords[i,1]/20) for i in 1:n] .+ randn(rng, n) .* 0.5

        t = @benchmark gwr_fit($y, $X, $coords; bandwidth=20.0)
        push!(entries, entry_from_trial("gwr_fit (n=$n, p=3, bw=20)", "spatial_reg", t, n))

        if n <= 150
            t = @benchmark bandwidth_aic($y, $X, $coords; n_candidates=5)
            push!(entries, entry_from_trial("bandwidth_aic (n=$n, cands=5)", "spatial_reg", t, n))
        end
    end

    foreach(print_entry, entries)
    entries
end

function bench_gp(rng)
    using GaussianProcessHealth
    entries = BenchmarkEntry[]
    println("\n▶ Gaussian Processes (Vol 6 — GaussianProcessHealth)")

    for n in [30, 100, 300]
        X = rand(rng, n, 2) .* 10
        y = [sin(X[i,1]) + cos(X[i,2]) + randn(rng)*0.1 for i in 1:n]
        k = SquaredExponential(1.0, 1.0)

        t = @benchmark gp_fit($X, $y, $k; σ²_noise=0.01)
        push!(entries, entry_from_trial("gp_fit/SE (n=$n, d=2)", "gp", t, n))

        model = gp_fit(X, y, k; σ²_noise=0.01)
        X_test = rand(rng, 20, 2) .* 10
        t = @benchmark gp_predict($model, $X_test)
        push!(entries, entry_from_trial("gp_predict (n=$n, m=20)", "gp", t, n))

        if n <= 100
            t = @benchmark optimize_hyperparams!($k, $X, $y; σ²_noise=0.01, n_restarts=2)
            push!(entries, entry_from_trial("optimize_hyperparams (n=$n, restarts=2)", "gp", t, n))
        end
    end

    foreach(print_entry, entries)
    entries
end

function bench_causal(rng)
    using CausalInference, PolicyEval
    entries = BenchmarkEntry[]
    println("\n▶ Causal Inference (Vol 11)")

    for n in [200, 1000, 5000]
        X = randn(rng, n, 5)
        D = Float64.(rand(rng, n) .> 0.5)
        y = 2.0 .* D .+ X * [1.0, 0.5, -0.3, 0.2, -0.1] .+ randn(rng, n)
        ps = 1.0 ./ (1.0 .+ exp.(-(X * [0.5, 0.3, -0.2, 0.1, -0.4])))

        t = @benchmark ps_fit($D, $X)
        push!(entries, entry_from_trial("ps_fit (n=$n, p=5)", "causal", t, n))

        t = @benchmark ipw_ate($D, $y, $ps; n_boot=50, rng=$rng)
        push!(entries, entry_from_trial("ipw_ate (n=$n, boot=50)", "causal", t, n))

        t = @benchmark aipw_ate($D, $y, $ps, $X; n_boot=50, rng=$rng)
        push!(entries, entry_from_trial("aipw_ate (n=$n, boot=50)", "causal", t, n))
    end

    # DiD
    for n in [100, 500]
        y = vcat(randn(rng, n), randn(rng, n) .+ 1.5 .* vcat(ones(n÷2), zeros(n÷2)))
        treat = vcat(vcat(ones(n÷2), zeros(n÷2)), vcat(ones(n÷2), zeros(n÷2)))
        post = vcat(zeros(n), ones(n))
        t = @benchmark did_2x2($y, $treat, $post; n_boot=100, rng=$rng)
        push!(entries, entry_from_trial("did_2x2 (n=$n, boot=100)", "causal", t, n))
    end

    foreach(print_entry, entries)
    entries
end

function bench_optimization(rng)
    using FacilityLocation, ResourceAllocation
    entries = BenchmarkEntry[]
    println("\n▶ Optimization (Vol 12)")

    for (n, m) in [(20, 10), (50, 20), (100, 30)]
        demand = rand(rng, n, 2) .* 100
        candidates = rand(rng, m, 2) .* 100
        pop = rand(rng, 1000:50000, n) .|> Float64

        t = @benchmark p_median($demand, $candidates, 5; weights=$pop, rng=$rng)
        push!(entries, entry_from_trial("p_median (n=$n, m=$m, p=5)", "optimization", t, n))

        t = @benchmark set_cover($demand, $candidates; coverage_radius=40.0, weights=$pop)
        push!(entries, entry_from_trial("set_cover (n=$n, m=$m, r=40)", "optimization", t, n))
    end

    # MDP
    for n_states in [10, 50, 200]
        R = rand(rng, n_states, 4) .* 10
        P = zeros(n_states, n_states, 4)
        for a in 1:4, s in 1:n_states
            P[s, :, a] = rand(rng, n_states)
            P[s, :, a] ./= sum(P[s, :, a])
        end
        t = @benchmark value_iteration($R, $P, 0.95)
        push!(entries, entry_from_trial("value_iteration (S=$n_states, A=4)", "optimization", t, n_states))
    end

    foreach(print_entry, entries)
    entries
end

function bench_disease_mapping(rng)
    using DiseaseMapping
    entries = BenchmarkEntry[]
    println("\n▶ Disease Mapping (Vol 10 — DiseaseMapping)")

    for n in [50, 200, 500]
        obs = rand(rng, 10:50, n)
        exp_cases = fill(30, n)

        t = @benchmark batch_smr($obs, $exp_cases)
        push!(entries, entry_from_trial("batch_smr (n=$n)", "disease_mapping", t, n))

        t = @benchmark eb_smooth($obs, $exp_cases)
        push!(entries, entry_from_trial("eb_smooth (n=$n)", "disease_mapping", t, n))
    end

    # Spatial scan (small due to combinatorial nature)
    coords = rand(rng, 30, 2) .* 100
    obs_sm = rand(rng, 10:50, 30)
    exp_sm = fill(25, 30)
    t = @benchmark spatial_scan($obs_sm, $exp_sm, $coords; max_radius=30.0)
    push!(entries, entry_from_trial("spatial_scan (n=30)", "disease_mapping", t, 30))

    foreach(print_entry, entries)
    entries
end

# ──────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────

const SUITES = Dict(
    "geostat"          => bench_geostat,
    "point_patterns"   => bench_point_patterns,
    "epidemic"         => bench_epidemic,
    "surveillance"     => bench_surveillance,
    "time_series"      => bench_time_series,
    "survival"         => bench_survival,
    "spatial_reg"      => bench_spatial_regression,
    "gp"               => bench_gp,
    "causal"           => bench_causal,
    "optimization"     => bench_optimization,
    "disease_mapping"  => bench_disease_mapping,
)

function main()
    rng = MersenneTwister(12345)
    save_baseline = "--save" in ARGS
    do_compare = "--compare" in ARGS
    filter_suite = filter(a -> !startswith(a, "-"), ARGS)

    suites_to_run = if isempty(filter_suite)
        sort(collect(keys(SUITES)))
    else
        filter(s -> s in keys(SUITES), filter_suite)
    end

    println("=" ^ 90)
    println("  GEO-JULIA PERFORMANCE BENCHMARKS")
    println("  Julia $(VERSION) — $(Dates.format(now(), "yyyy-mm-dd HH:MM"))")
    println("  Suites: $(join(suites_to_run, ", "))")
    println("=" ^ 90)

    all_entries = BenchmarkEntry[]
    for suite_name in suites_to_run
        try
            entries = SUITES[suite_name](rng)
            append!(all_entries, entries)
        catch e
            println("  ⚠ Suite '$suite_name' failed: $e")
        end
    end

    # Summary
    println("\n" * "=" ^ 90)
    println("  SUMMARY — $(length(all_entries)) benchmarks across $(length(suites_to_run)) suites")
    println("=" ^ 90)
    @printf("  %-45s  %12s  %12s  %6s\n", "Benchmark", "Median", "Memory", "Allocs")
    println("  " * "-" ^ 80)
    foreach(print_entry, all_entries)

    # Save / compare
    timestamp = Dates.format(now(), "yyyymmdd_HHMM")
    results_path = joinpath(RESULTS_DIR, "bench_$timestamp.json")
    save_results(all_entries, results_path)

    if save_baseline
        save_results(all_entries, BASELINE_PATH)
        println("✓ Saved as baseline")
    end

    if do_compare
        passed = compare_to_baseline(all_entries)
        if !passed
            exit(1)
        end
    end
end

main()
