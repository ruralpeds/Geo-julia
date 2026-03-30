#!/usr/bin/env julia
# scripts/benchmark_suite.jl — Cross-volume algorithm benchmark suite
# Chapter 47 — Open-Source Healthcare GIS Textbook in Julia
#
# Compares all major algorithms across Vols 3–7 on standardised healthcare
# datasets.  Reports: throughput, memory allocation, and accuracy metrics.

using Statistics, LinearAlgebra, Random, DataFrames, Printf

# ── Benchmark timing utility ──────────────────────────────────────────────────

"""
    @benchmark_timed expr n_warmup n_runs

Run `expr` n_warmup times (ignored), then n_runs times and return
(median_ms, alloc_bytes, result).
"""
macro benchmark_timed(expr, n_warmup=3, n_runs=10)
    quote
        # Warmup
        for _ in 1:$(n_warmup)
            $(esc(expr))
        end
        GC.gc()

        times_ns = Float64[]
        for _ in 1:$(n_runs)
            t0 = time_ns()
            r  = $(esc(expr))
            push!(times_ns, Float64(time_ns() - t0))
        end
        (median_ms = median(times_ns) / 1e6,
         p95_ms    = quantile(times_ns, 0.95) / 1e6,
         min_ms    = minimum(times_ns) / 1e6)
    end
end

# ── Benchmark result types ────────────────────────────────────────────────────

struct BenchmarkResult
    algorithm    :: String
    volume       :: Int
    category     :: String
    dataset_size :: NamedTuple
    median_ms    :: Float64
    p95_ms       :: Float64
    accuracy     :: Union{Float64, Nothing}
    metric_name  :: String
    notes        :: String
end

# ── Synthetic benchmark datasets ─────────────────────────────────────────────

function make_regression_data(n::Int, p::Int; rng=MersenneTwister(42))
    X = randn(rng, n, p)
    β = randn(rng, p)
    y = X * β .+ 0.1*randn(rng, n)
    X, y
end

function make_panel_data(n::Int, T::Int; rng=MersenneTwister(42))
    rows = []
    for i in 1:n, t in 1:T
        push!(rows, (id=lpad(i,3,'0'), year=2010+t,
                     treated=Int(i <= n÷2), outcome=randn(rng),
                     x1=randn(rng), z=randn(rng)))
    end
    DataFrame(rows)
end

function make_spatial_data(n::Int; rng=MersenneTwister(42))
    X = hcat(40.0 .+ randn(rng, n), -100.0 .+ randn(rng, n))
    y = sin.(X[:,1]) .+ 0.1*randn(rng, n)
    X, y
end

# ── Algorithm benchmark runners ───────────────────────────────────────────────

function bench_matrix_ops(sizes)
    results = BenchmarkResult[]
    for n in sizes
        A = randn(n, n)
        b = randn(n)

        # Cholesky (GP core operation)
        B = A'A + n*I
        t_chol = @benchmark_timed cholesky(Symmetric(B)) 3 5
        push!(results, BenchmarkResult(
            "Cholesky (GP)", 6, "Linear Algebra",
            (n=n, p=n), t_chol.median_ms, t_chol.p95_ms,
            nothing, "—", "Core GP kernel inversion"
        ))

        # SVD
        t_svd = @benchmark_timed svd(A) 2 3
        push!(results, BenchmarkResult(
            "SVD", 3, "Linear Algebra",
            (n=n, p=n), t_svd.median_ms, t_svd.p95_ms,
            nothing, "—", "Decomposition reference"
        ))
    end
    results
end

function bench_causal_inference(n_units, n_years)
    results = BenchmarkResult[]
    df = make_panel_data(n_units, n_years)

    # DiD
    t = @benchmark_timed begin
        # Manual TWFE timing (avoid package dependency in benchmark)
        n = nrow(df)
        ids = unique(df.id); T = unique(df.year)
        Y  = df.outcome
        D  = df.treated .* (df.year .>= 2015)
        # Demeaning
        unit_means = Dict(id => mean(Y[df.id .== id]) for id in ids)
        time_means = Dict(yr => mean(Y[df.year .== yr]) for yr in T)
        grand_mean = mean(Y)
        Y_dm = [Y[i] - unit_means[df.id[i]] - time_means[df.year[i]] + grand_mean for i in 1:n]
        D_dm = [D[i] - mean(D[df.id .== df.id[i]]) -
                mean(D[df.year .== df.year[i]]) + mean(D) for i in 1:n]
        att = sum(D_dm .* Y_dm) / max(sum(D_dm.^2), 1e-12)
        att
    end 3 8
    push!(results, BenchmarkResult(
        "TWFE DiD", 6, "Causal Inference",
        (units=n_units, years=n_years, obs=n_units*n_years),
        t.median_ms, t.p95_ms, nothing, "—",
        "Two-way FE demeaning"
    ))

    results
end

function bench_gp_inference(n_train_sizes)
    results = BenchmarkResult[]
    for n in n_train_sizes
        X, y = make_spatial_data(n)

        # Exact GP (Cholesky)
        t = @benchmark_timed begin
            K = [exp(-sum((X[i,:] .- X[j,:]).^2) / 200.0)
                 for i in 1:n, j in 1:n]
            K_n = K + (0.01 + 1e-8)*I(n)
            L = cholesky(Symmetric(K_n)).L
            α = L' \ (L \ y)
            log_ml = -0.5*dot(y, α) - sum(log.(diag(L))) - 0.5*n*log(2π)
            log_ml
        end 2 5
        push!(results, BenchmarkResult(
            "Exact GP", 6, "Gaussian Processes",
            (n_train=n,), t.median_ms, t.p95_ms, nothing, "—",
            "O(n³) Cholesky"
        ))
    end
    results
end

function bench_neural_networks(configs)
    results = BenchmarkResult[]
    rng = MersenneTwister(42)

    for (n, p, h) in configs
        X = randn(rng, p, n)
        y = randn(rng, n)
        W1 = randn(rng, h, p) .* sqrt(2/p)
        b1 = zeros(h)
        W2 = randn(rng, 1, h) .* sqrt(2/h)
        b2 = zeros(1)

        # MLP forward pass
        t = @benchmark_timed begin
            h1 = max.(W1 * X .+ b1, 0)
            ŷ  = W2 * h1 .+ b2
            ŷ
        end 5 20
        push!(results, BenchmarkResult(
            "MLP forward (h=$h)", 7, "Deep Learning",
            (n=n, p=p, hidden=h), t.median_ms, t.p95_ms, nothing, "—",
            "ReLU activation"
        ))
    end
    results
end

function bench_mcmc(dims, n_iters)
    results = BenchmarkResult[]

    for d in dims
        # Metropolis-Hastings step timing
        θ = zeros(d)
        log_p(θ) = -0.5*sum(θ.^2)
        step = 0.3
        rng = MersenneTwister(1)

        t = @benchmark_timed begin
            θ_prop = θ .+ step .* randn(rng, d)
            α = log_p(θ_prop) - log_p(θ)
            if log(rand(rng)) < α
                θ_prop
            else
                θ
            end
        end 5 50
        push!(results, BenchmarkResult(
            "MH step (d=$d)", 7, "MCMC",
            (dim=d, iters=n_iters), t.median_ms, t.p95_ms, nothing, "—",
            "Random-walk MH"
        ))
    end
    results
end

# ── Accuracy benchmarks ───────────────────────────────────────────────────────

function bench_accuracy()
    results = BenchmarkResult[]
    rng = MersenneTwister(42)

    # Linear regression accuracy vs sample size
    for n in [50, 100, 500]
        X, y = make_regression_data(n, 4; rng=rng)
        # OLS
        X_aug = hcat(ones(n), X)
        β_ols = (X_aug' * X_aug + 1e-8I) \ (X_aug' * y)
        ŷ = X_aug * β_ols
        rmse = sqrt(mean((ŷ .- y).^2))
        push!(results, BenchmarkResult(
            "OLS (n=$n)", 3, "Regression Accuracy",
            (n=n, p=4), 0.0, 0.0, rmse, "RMSE", "Ridge λ=1e-8"
        ))

        # MLP (2 hidden layers)
        W1 = randn(rng, 16, 4) .* sqrt(0.5)
        b1 = zeros(16)
        W2 = randn(rng, 1, 16) .* sqrt(1/16)
        b2 = zeros(1)
        h1 = max.(W1 * X' .+ b1, 0)
        ŷ_mlp = vec(W2 * h1 .+ b2)
        rmse_mlp = sqrt(mean((ŷ_mlp .- y).^2))
        push!(results, BenchmarkResult(
            "MLP random init (n=$n)", 7, "Regression Accuracy",
            (n=n, p=4), 0.0, 0.0, rmse_mlp, "RMSE",
            "Untrained reference"
        ))
    end
    results
end

# ── Report formatting ─────────────────────────────────────────────────────────

function format_benchmark_table(results::Vector{BenchmarkResult})
    df = DataFrame(
        Algorithm    = [r.algorithm for r in results],
        Volume       = [r.volume for r in results],
        Category     = [r.category for r in results],
        Dataset      = [join(["$(k)=$(v)" for (k,v) in pairs(r.dataset_size)], ", ")
                        for r in results],
        Median_ms    = [r.median_ms for r in results],
        P95_ms       = [r.p95_ms for r in results],
        Accuracy     = [isnothing(r.accuracy) ? "—" :
                        string(round(r.accuracy; digits=4)) for r in results],
        Metric       = [r.metric_name for r in results],
    )
    df
end

function print_benchmark_report(results::Vector{BenchmarkResult})
    categories = unique(r.category for r in results)
    for cat in categories
        cat_results = filter(r -> r.category == cat, results)
        println("\n┌─ $cat")
        println("│  $(rpad("Algorithm", 35)) $(rpad("Dataset", 25)) $(rpad("Median", 10)) $(rpad("P95", 10)) Accuracy")
        println("│  " * "─"^90)
        for r in cat_results
            ds = join(["$(v)" for v in values(r.dataset_size)], "×")
            acc = isnothing(r.accuracy) ? "—" : string(round(r.accuracy; digits=4))
            @printf("│  %-35s %-25s %8.2f ms %8.2f ms %s\n",
                    r.algorithm, ds, r.median_ms, r.p95_ms, acc)
        end
        print("└")
    end
    println()
end

# ── Main ──────────────────────────────────────────────────────────────────────

"""
    run_benchmark_suite(; quick) -> DataFrame

Run all benchmarks and return results table.
quick=true runs a fast subset suitable for CI.
"""
function run_benchmark_suite(; quick::Bool=false)
    println("=" ^ 70)
    println("Healthcare GIS Textbook — Cross-Volume Benchmark Suite")
    println("Julia $(VERSION)  |  $(Threads.nthreads()) thread(s)")
    println("=" ^ 70)

    all_results = BenchmarkResult[]

    println("\nLinear algebra primitives...")
    mat_sizes = quick ? [50, 100] : [50, 100, 200, 500]
    append!(all_results, bench_matrix_ops(mat_sizes))

    println("Causal inference...")
    append!(all_results, bench_causal_inference(30, 8))

    println("GP inference...")
    gp_sizes = quick ? [20, 50] : [20, 50, 100, 200]
    append!(all_results, bench_gp_inference(gp_sizes))

    println("Neural networks...")
    nn_configs = quick ? [(100, 8, 32)] : [(100, 8, 32), (500, 16, 64), (1000, 32, 128)]
    append!(all_results, bench_neural_networks(nn_configs))

    println("MCMC...")
    mcmc_dims = quick ? [2, 5] : [2, 5, 10, 20]
    append!(all_results, bench_mcmc(mcmc_dims, 1000))

    println("Accuracy benchmarks...")
    append!(all_results, bench_accuracy())

    println()
    print_benchmark_report(all_results)

    df = format_benchmark_table(all_results)
    println("Total benchmarks: $(nrow(df))")
    df
end

# Run if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    df = run_benchmark_suite(; quick=false)
    println(df)
end
