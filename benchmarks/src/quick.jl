#=
Quick benchmark — runs a minimal subset for fast iteration.
Takes ~1 minute instead of ~15.

Usage:
    julia --project=benchmarks benchmarks/src/quick.jl
=#

using BenchmarkTools, Statistics, Random, Printf

BenchmarkTools.DEFAULT_PARAMETERS.samples = 3
BenchmarkTools.DEFAULT_PARAMETERS.seconds = 5
BenchmarkTools.DEFAULT_PARAMETERS.evals = 1

rng = MersenneTwister(42)

println("=" ^ 70)
println("  QUICK BENCHMARKS (smoke test)")
println("=" ^ 70)

format_time(ns) = ns < 1e3 ? @sprintf("%.0f ns", ns) :
                  ns < 1e6 ? @sprintf("%.1f μs", ns/1e3) :
                  ns < 1e9 ? @sprintf("%.2f ms", ns/1e6) :
                             @sprintf("%.3f s", ns/1e9)

function quick_bench(name, expr)
    t = @benchmark $expr
    m = median(t).time
    @printf("  %-40s  %12s  %8.1f KiB\n", name, format_time(m), t.memory/1024)
end

# Geostat
println("\n▶ Geostatistics")
using GeostatHealth
coords = rand(rng, 100, 2) .* 100
z = [sin(coords[i,1]/20) + randn(rng)*0.1 for i in 1:100]
ev = empirical_variogram(coords, z; n_lags=10)
vm = fit_variogram(ev; model=:spherical)
ok = ordinary_kriging(z, coords, vm)
new_pts = rand(rng, 10, 2) .* 100

quick_bench("empirical_variogram (n=100)", empirical_variogram(coords, z; n_lags=10))
quick_bench("ordinary_kriging (n=100)", ordinary_kriging(z, coords, vm))
quick_bench("ok_predict (n=100, m=10)", ok_predict(ok, new_pts))

# Epidemic
println("\n▶ Epidemic")
using InfectiousDisease
quick_bench("sir (N=100k)", sir(100_000, 10, 0.35, 0.12; t_end=300.0, dt=1.0))
quick_bench("seir (N=100k)", seir(100_000, 5, 10, 0.35, 0.2, 0.12; t_end=300.0, dt=1.0))

# Surveillance
println("\n▶ Surveillance")
using SurveillanceSystems
cases = 10.0 .+ randn(rng, 365) .* 3.0
quick_bench("cusum (n=365)", cusum(cases; μ₀=10.0, σ₀=3.0, k=1.0, h=5.0))
quick_bench("ewma (n=365)", ewma(cases; λ=0.2, L=2.7, μ₀=10.0, σ₀=3.0))

# Time Series
println("\n▶ Time Series")
using TimeSeriesHealth
ts = cumsum(randn(rng, 200)) .+ 50
quick_bench("arima_fit(2,1,1) (n=200)", arima_fit(ts, 2, 1, 1))
quick_bench("kalman_filter (n=200)", kalman_filter(ts, 1.0, 0.1))

# Causal
println("\n▶ Causal Inference")
using CausalInference
X = randn(rng, 500, 5)
D = Float64.(rand(rng, 500) .> 0.5)
y = 2.0 .* D .+ X * ones(5) .+ randn(rng, 500)
quick_bench("ps_fit (n=500, p=5)", ps_fit(D, X))

# Optimization
println("\n▶ Optimization")
using FacilityLocation
demand = rand(rng, 30, 2) .* 100
cands = rand(rng, 12, 2) .* 100
quick_bench("p_median (n=30, m=12, p=3)", p_median(demand, cands, 3; rng=rng))

println("\n" * "=" ^ 70)
println("  QUICK BENCHMARKS COMPLETE")
println("=" ^ 70)
