#!/usr/bin/env julia
# scripts/spatial_pipeline.jl — End-to-end GWR + diagnostics pipeline
# Chapter 49 — Open-Source Healthcare GIS Textbook in Julia

using Statistics, LinearAlgebra, Random, DataFrames, Printf

const SRPATH = joinpath(@__DIR__, "..", "packages", "SpatialRegression")
const USE_SR = isdir(SRPATH)

if USE_SR
    push!(LOAD_PATH, joinpath(SRPATH, "src"))
    include(joinpath(SRPATH, "src", "SpatialRegression.jl"))
    using .SpatialRegression
end

# ── Synthetic county data ─────────────────────────────────────────────────────

"""
    make_county_spatial_data(n; rng) -> NamedTuple

Simulate spatially structured county-level healthcare access data.
DGP: access = f(poverty, rurality, distance) + spatial error
"""
function make_county_spatial_data(n::Int=53; rng=MersenneTwister(42))
    # County centroids on a grid (approximating ND geography)
    n_row = ceil(Int, sqrt(n)); n_col = ceil(Int, n/n_row)
    lats = [44.0 + (i-1)*0.5 for i in 1:n_row for _ in 1:n_col][1:n]
    lons = [-104.0 + (j-1)*0.8 for _ in 1:n_row for j in 1:n_col][1:n]
    lats .+= 0.1*randn(rng, n); lons .+= 0.1*randn(rng, n)
    coords = hcat(lats, lons)

    # Covariates
    poverty_rate  = clamp.(0.12 .+ 0.06*randn(rng, n), 0.03, 0.45)
    rurality      = clamp.(0.5 .+ 0.3*randn(rng, n), 0.05, 0.99)
    dist_hospital = exp.(2.5 .+ 0.7*randn(rng, n))   # log-normal (km)

    # Spatially varying coefficient for poverty (β₁ higher in west)
    β_poverty = -0.003 .- 0.002*(lons .+ 104) ./ 4   # more negative westward
    β_rural   = fill(-0.002, n)
    β_dist    = fill(-0.00002, n)
    intercept = 0.008

    y_access = intercept .+ β_poverty .* poverty_rate .+
               β_rural .* rurality .+ β_dist .* dist_hospital .+
               0.0005*randn(rng, n)
    y_access = max.(y_access, 0.0001)

    X = hcat(poverty_rate, rurality, dist_hospital)
    feature_names = ["poverty_rate", "rurality", "dist_hospital_km"]

    (coords=coords, X=X, y=y_access, feature_names=feature_names,
     lats=lats, lons=lons,
     β_poverty_true=β_poverty, β_rural_true=β_rural)
end

# ── Pipeline steps ────────────────────────────────────────────────────────────

function step1_ols_baseline(y, X, feature_names)
    println("\n── Step 1: OLS Baseline ──────────────────────────────────")
    n, p = size(X)
    X_aug = hcat(ones(n), X)
    β = (X_aug'X_aug + 1e-8I) \ X_aug'y
    ŷ = X_aug * β
    e = y .- ŷ
    rmse = sqrt(mean(e.^2))
    r2   = 1 - sum(e.^2) / sum((y .- mean(y)).^2)

    println("  OLS Coefficients:")
    println("    Intercept: $(round(β[1];digits=5))")
    for (i, nm) in enumerate(feature_names)
        println("    $(rpad(nm,20)): $(round(β[i+1];digits=5))")
    end
    @printf("  RMSE: %.5f   R²: %.4f\n", rmse, r2)
    e, β
end

function step2_spatial_diagnostics(e, X, W)
    println("\n── Step 2: Spatial Diagnostics ──────────────────────────")
    if !USE_SR
        println("  (SpatialRegression not loaded — skipping)")
        return nothing
    end
    diag = run_diagnostics(e, X, W; permutations=299)
    println(diag)
    diag
end

function step3_global_spatial_models(y, X, W, feature_names)
    println("\n── Step 3: Global Spatial Models ────────────────────────")
    if !USE_SR
        println("  (SpatialRegression not loaded — skipping)")
        return
    end
    println("  Fitting Spatial Lag model...")
    m_lag = spatial_lag_fit(y, X, W; feature_names=feature_names)
    println(m_lag)
    println()
    println("  Fitting Spatial Error model...")
    m_err = spatial_error_fit(y, X, W; feature_names=feature_names)
    println(m_err)
    println()
    println("  Model comparison (lower AIC = better):")
    @printf("    Spatial Lag   AIC: %.2f\n", m_lag.aic)
    @printf("    Spatial Error AIC: %.2f\n", m_err.aic)
    m_lag, m_err
end

function step4_gwr(y, X, coords, feature_names)
    println("\n── Step 4: Geographically Weighted Regression ───────────")
    if !USE_SR
        println("  (SpatialRegression not loaded — skipping)")
        return
    end

    println("  Selecting bandwidth via AIC-c...")
    bw = bandwidth_aic(y, X, coords; n_candidates=8)
    @printf("  Optimal bandwidth: %.3f degrees\n", bw)

    println("  Fitting GWR...")
    m_gwr = gwr_fit(y, X, coords; bandwidth=bw, feature_names=feature_names)
    println(m_gwr)

    # Summarise spatial variability of local coefficients
    println("\n  Spatial non-stationarity (IQR of local coefficients):")
    for (j, nm) in enumerate(m_gwr.feature_names)
        lo_coef = m_gwr.local_β[:, j]
        iqr = quantile(lo_coef, 0.75) - quantile(lo_coef, 0.25)
        @printf("    %-20s  IQR=%.5f  [p25=%.4f, p75=%.4f]\n",
                nm, iqr, quantile(lo_coef, 0.25), quantile(lo_coef, 0.75))
    end

    m_gwr
end

function step5_gwrf(y, X, coords, rng)
    println("\n── Step 5: Geographically Weighted Random Forest ─────────")
    if !USE_SR
        println("  (SpatialRegression not loaded — skipping)")
        return
    end
    println("  Fitting GW-RF...")
    m_rf = gwrf_fit(y, X, coords; bandwidth=2.5, n_trees=30, max_depth=3, rng=rng)
    @printf("  Global RMSE (GW-RF): %.5f\n", m_rf.global_rmse)

    # Compare to OLS
    X_aug = hcat(ones(size(X,1)), X)
    β_ols = (X_aug'X_aug + 1e-8I) \ X_aug'y
    ŷ_ols = X_aug * β_ols
    rmse_ols = sqrt(mean((y .- ŷ_ols).^2))
    @printf("  Global RMSE (OLS):   %.5f\n", rmse_ols)
    println("  GW-RF advantage: $(round(100*(rmse_ols-m_rf.global_rmse)/rmse_ols;digits=1))% RMSE reduction")
    m_rf
end

# ── Main ──────────────────────────────────────────────────────────────────────

function main(n_counties::Int=53; rng=MersenneTwister(42))
    println("="^60)
    println("  SPATIAL REGRESSION PIPELINE")
    println("  n=$(n_counties) counties | $(now_str())")
    println("="^60)

    data = make_county_spatial_data(n_counties; rng=rng)
    y, X, coords = data.y, data.X, data.coords
    feature_names = data.feature_names

    # Build spatial weights (4-nearest-neighbour, row-normalised)
    D = USE_SR ? distance_matrix(coords) :
        [sqrt(sum((coords[i,:] .- coords[j,:]).^2)) for i in 1:n_counties, j in 1:n_counties]
    W = zeros(n_counties, n_counties)
    for i in 1:n_counties
        order = sortperm(D[i,:])[2:5]
        W[i, order] .= 0.25
    end

    e_ols, β_ols = step1_ols_baseline(y, X, feature_names)
    diag = step2_spatial_diagnostics(e_ols, X, W)
    step3_global_spatial_models(y, X, W, feature_names)
    gwr_model = step4_gwr(y, X, coords, feature_names)
    gwrf_model = step5_gwrf(y, X, coords, rng)

    println("\n$(("="^60))")
    println("  Pipeline complete.")
    println("="^60)

    (data=data, W=W, gwr=gwr_model, gwrf=gwrf_model)
end

now_str() = string(Dates.now())[1:16]

if abspath(PROGRAM_FILE) == @__FILE__
    using Dates
    main()
end
