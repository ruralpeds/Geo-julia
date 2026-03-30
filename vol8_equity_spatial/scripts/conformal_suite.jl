#!/usr/bin/env julia
# scripts/conformal_suite.jl — Comparative conformal coverage benchmarks
# Chapter 50 — Open-Source Healthcare GIS Textbook in Julia
#
# Compares split conformal, CQR, and jackknife+ across:
# - Coverage rate (should be ≥ 1-α)
# - Interval width (smaller = more efficient)
# - Conditional coverage (coverage by subgroup)

using Statistics, LinearAlgebra, Random, DataFrames, Printf

const CHPATH = joinpath(@__DIR__, "..", "packages", "ConformalHealth")
const USE_CH = isdir(CHPATH)

if USE_CH
    push!(LOAD_PATH, joinpath(CHPATH, "src"))
    include(joinpath(CHPATH, "src", "ConformalHealth.jl"))
    using .ConformalHealth
end

# ── Simple OLS predict factory ────────────────────────────────────────────────

function ols_factory(X_tr, y_tr)
    n, p = size(X_tr)
    X_aug = hcat(ones(n), X_tr)
    β = (X_aug'X_aug + 1e-8I) \ X_aug'y_tr
    X_new -> vec(hcat(ones(size(X_new,1)), X_new) * β)
end

# ── Data generation ───────────────────────────────────────────────────────────

"""
    make_conformal_data(n, p, σ_fn; rng)

Generate regression data with heteroskedastic noise for coverage benchmarks.
σ_fn(x) controls the noise level — methods with wider intervals in high-σ
regions demonstrate adaptive coverage.
"""
function make_conformal_data(n::Int, p::Int=4; rng=MersenneTwister(42),
                              σ_fn=x -> 0.3)
    X = randn(rng, n, p)
    β = randn(rng, p) .* 0.5
    σ = [σ_fn(X[i,:]) for i in 1:n]
    y = X * β .+ σ .* randn(rng, n)
    X, y, β, σ
end

# ── Coverage benchmarking ─────────────────────────────────────────────────────

struct BenchResult
    method    :: String
    coverage  :: Float64
    target    :: Float64
    mean_width :: Float64
    std_width :: Float64
    cond_coverage_lo :: Float64   # coverage in low-variance region
    cond_coverage_hi :: Float64   # coverage in high-variance region
    n_test    :: Int
end

function run_conformal_benchmarks(;
    n_train  :: Int = 300,
    n_calib  :: Int = 150,
    n_test   :: Int = 200,
    p        :: Int = 6,
    α        :: Float64 = 0.1,
    n_reps   :: Int = 5,
    rng              = MersenneTwister(42),
)
    results = BenchResult[]

    for rep in 1:n_reps
        rng_rep = MersenneTwister(rep * 1000)
        n_total = n_train + n_calib + n_test

        # Heteroskedastic DGP: noise ∝ first feature magnitude
        σ_fn = x -> 0.1 + 0.4 * abs(x[1])
        X, y, _, σ = make_conformal_data(n_total, p; rng=rng_rep, σ_fn=σ_fn)

        X_tr = X[1:n_train, :]
        y_tr = y[1:n_train]
        X_c  = X[n_train+1:n_train+n_calib, :]
        y_c  = y[n_train+1:n_train+n_calib]
        X_te = X[n_train+n_calib+1:end, :]
        y_te = y[n_train+n_calib+1:end]
        σ_te = σ[n_train+n_calib+1:end]

        # Mask for low/high variance test points
        mask_lo = σ_te .< median(σ_te)
        mask_hi = .!mask_lo

        pred_fn = ols_factory(X_tr, y_tr)

        # ── Method 1: Split conformal ─────────────────────────────────────
        if USE_CH
            cr = conformal_fit(pred_fn, X_c, y_c; α=α)
            r  = conformal_predict(cr, X_te)
            cov_all = mean((y_te .>= r.lower) .& (y_te .<= r.upper))
            cov_lo  = mean((y_te[mask_lo] .>= r.lower[mask_lo]) .& (y_te[mask_lo] .<= r.upper[mask_lo]))
            cov_hi  = mean((y_te[mask_hi] .>= r.lower[mask_hi]) .& (y_te[mask_hi] .<= r.upper[mask_hi]))
            push!(results, BenchResult("Split Conformal", cov_all, 1-α,
                                        mean(r.width), std(r.width), cov_lo, cov_hi, n_test))

            # ── Method 2: CQR ────────────────────────────────────────────────
            m_cqr = cqr_fit(X_tr, y_tr, X_c, y_c; α=α)
            df_cqr = cqr_predict(m_cqr, X_te)
            cov_cqr = mean((y_te .>= df_cqr.lower) .& (y_te .<= df_cqr.upper))
            cov_cqr_lo = mean((y_te[mask_lo] .>= df_cqr.lower[mask_lo]) .& (y_te[mask_lo] .<= df_cqr.upper[mask_lo]))
            cov_cqr_hi = mean((y_te[mask_hi] .>= df_cqr.lower[mask_hi]) .& (y_te[mask_hi] .<= df_cqr.upper[mask_hi]))
            push!(results, BenchResult("CQR", cov_cqr, 1-α,
                                        mean(df_cqr.width), std(df_cqr.width),
                                        cov_cqr_lo, cov_cqr_hi, n_test))
        end

        # ── Method 3: Jackknife+ (approximate) ───────────────────────────
        if USE_CH
            jr = jackknife_plus(ols_factory, X_tr[1:60,:], y_tr[1:60], X_te;
                                α=α, max_n_loo=30)
            cov_jk = mean((y_te .>= jr.lower) .& (y_te .<= jr.upper))
            cov_jk_lo = mean((y_te[mask_lo] .>= jr.lower[mask_lo]) .& (y_te[mask_lo] .<= jr.upper[mask_lo]))
            cov_jk_hi = mean((y_te[mask_hi] .>= jr.lower[mask_hi]) .& (y_te[mask_hi] .<= jr.upper[mask_hi]))
            push!(results, BenchResult("Jackknife+", cov_jk, 1-α,
                                        mean(jr.width), std(jr.width),
                                        cov_jk_lo, cov_jk_hi, n_test))
        end
    end

    results
end

function print_conformal_summary(results::Vector{BenchResult})
    methods = unique(r.method for r in results)
    println("\n" * "="^70)
    println("  CONFORMAL PREDICTION BENCHMARK SUMMARY")
    println("  α=0.10 (target coverage=0.90)")
    println("="^70)
    @printf("  %-20s  %s  %s  %s  %s  %s\n",
            "Method", "Coverage", "Target", "Width(μ)", "Cov_lo", "Cov_hi")
    println("  " * "-"^65)

    for method in methods
        mrs = filter(r -> r.method == method, results)
        cov_mean  = mean(r.coverage for r in mrs)
        w_mean    = mean(r.mean_width for r in mrs)
        cov_lo    = mean(r.cond_coverage_lo for r in mrs)
        cov_hi    = mean(r.cond_coverage_hi for r in mrs)
        target    = mrs[1].target
        ok = cov_mean >= target - 0.02 ? "✓" : "✗"
        @printf("  %-20s  %.3f  %s  %.3f    %.3f   %.3f   %s\n",
                method, cov_mean, "$(target)", w_mean, cov_lo, cov_hi, ok)
    end

    println("\n  Notes:")
    println("  • Coverage ≥ target required by conformal guarantee")
    println("  • Lower width = more efficient (narrower intervals)")
    println("  • CQR adapts width to local variance (Cov_lo ≠ Cov_hi)")
    println("="^70)
end

# ── Main ──────────────────────────────────────────────────────────────────────

function main(; quick::Bool=false)
    println("Running conformal coverage benchmarks...")
    n_reps = quick ? 2 : 5
    results = run_conformal_benchmarks(; n_reps=n_reps)
    print_conformal_summary(results)
    DataFrame(
        method   = [r.method for r in results],
        coverage = [r.coverage for r in results],
        width    = [r.mean_width for r in results],
        cov_lo   = [r.cond_coverage_lo for r in results],
        cov_hi   = [r.cond_coverage_hi for r in results],
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
