#!/usr/bin/env julia
# pipeline/03_spatial_analysis.jl
# North Dakota Analysis — Spatial Analysis Layer
# Computes: queen weights, E2SFCA access, Moran's I, LISA, spatial regression
# Vol 4 — Chapter 29.1.3

include("02_prepare_spatial.jl")

# Load spatial analysis packages
import Pkg
for pkg in ["SpatialStats"]
    Pkg.activate(joinpath(@__DIR__, "..", "..", "julia_geo_packages", "packages", pkg))
end
Pkg.activate(joinpath(@__DIR__, ".."))

# Try loading SpatialStats
try
    using SpatialStats
catch
    @warn "SpatialStats.jl not loaded from workspace. Ensure packages are installed."
end

using Statistics, DataFrames, CSV
using SparseArrays

# ── Synthetic queen weights for ND (53 counties) ──────────────────────────────
# When geometries are not available (shapefile not downloaded),
# build a synthetic chain weights matrix based on sorted centroid distance.
function build_synthetic_nd_weights(n::Int)
    @info "Building synthetic contiguity weights for $(n) counties..."
    Is = Int[]; Js = Int[]; Vs = Float64[]
    for i in 1:n-1
        push!(Is, i, i+1); push!(Js, i+1, i); push!(Vs, 1.0, 1.0)
    end
    # Add some cross-connections to approximate ND topology
    for i in 1:n-8
        push!(Is, i, i+8); push!(Js, i+8, i); push!(Vs, 1.0, 1.0)
    end
    W = sparse(Is, Js, Vs, n, n)
    row_sums = vec(sum(W; dims=2))
    rows, cols, vals = findnz(W)
    for k in eachindex(rows)
        vals[k] /= row_sums[rows[k]]
    end
    W = sparse(rows, cols, vals, n, n)
    SpatialStats.SpatialWeights(W, n,
        SpatialStats.RowStandardizedStyle(),
        SpatialStats.QueenTransform(), 0,
        mean(vec(sum(W .!= 0; dims=2))),
        minimum(vec(sum(W .!= 0; dims=2))),
        maximum(vec(sum(W .!= 0; dims=2))))
end

# ── E2SFCA accessibility (simplified) ─────────────────────────────────────────
function compute_e2sfca_access(nd_df, prov_df; catchment_km=50.0)
    n = nrow(nd_df)
    # Provider locations
    prov_lat = Float64.(coalesce.(prov_df.lat, 46.5))
    prov_lon = Float64.(coalesce.(prov_df.lon, -100.5))
    n_prov = length(prov_lat)

    # County centroid locations
    pop_lat = Float64.(coalesce.(nd_df.centroid_lat, 46.5))
    pop_lon = Float64.(coalesce.(nd_df.centroid_lon, -100.5))
    pop     = Float64.(coalesce.(nd_df.total_pop, 1000.0))

    # Gaussian decay E2SFCA
    σ_km = catchment_km / 3.0
    access = zeros(Float64, n)

    # Step 1: physician-to-population ratio for each provider catchment
    for j in 1:n_prov
        total_pop_j = 0.0
        weights = Float64[]
        pop_in_catchment = Int[]

        for i in 1:n
            d = SpatialStats.haversine_km(prov_lat[j], prov_lon[j], pop_lat[i], pop_lon[i])
            if d <= catchment_km
                w = exp(-d^2 / (2σ_km^2))
                total_pop_j += w * pop[i]
                push!(weights, w)
                push!(pop_in_catchment, i)
            end
        end

        # Step 2: sum physician-to-pop ratios within each county catchment
        R_j = total_pop_j > 0 ? 1.0 / total_pop_j : 0.0
        for (k, i) in enumerate(pop_in_catchment)
            d = SpatialStats.haversine_km(prov_lat[j], prov_lon[j], pop_lat[i], pop_lon[i])
            w = exp(-d^2 / (2σ_km^2))
            access[i] += w * R_j
        end
    end

    access
end

# ── Main analysis function ─────────────────────────────────────────────────────
function run_spatial_analysis(nd_df, prov_geocoded;
                               catchment_km=50.0, alpha=0.05)
    n = nrow(nd_df)
    @info "Running spatial analysis for $(n) counties..."

    # ── Build spatial weights ────────────────────────────────────────────────
    w = if hasproperty(nd_df, :geometry) && !isnothing(nd_df.geometry[1])
        @info "Building queen contiguity weights from geometries..."
        queen_weights(nd_df)
    else
        @info "Using synthetic weights (no geometry available)"
        build_synthetic_nd_weights(n)
    end
    @info "Mean neighbors: $(round(w.mean_neighbors; digits=2)), islands: $(w.island_count)"

    # ── E2SFCA access scores ─────────────────────────────────────────────────
    @info "Computing E2SFCA access scores (catchment=$(catchment_km)km)..."
    nd_df.access_score = compute_e2sfca_access(nd_df, prov_geocoded; catchment_km)

    # ── Moran's I for key variables ──────────────────────────────────────────
    vars_to_test = [:access_score, :poverty_pct, :uninsured_pct]
    moran_results = Dict{Symbol, Any}()

    for var in vars_to_test
        hasproperty(nd_df, var) || continue
        vals = Float64.(coalesce.(nd_df[!, var], median(skipmissing(nd_df[!, var]))))
        r = moran(vals, w; permutations=999)
        moran_results[var] = r
        @info "Moran's I ($(var)) = $(round(r.I; digits=4)), p = $(round(r.p_value; digits=4))"
    end

    # ── LISA clusters ────────────────────────────────────────────────────────
    @info "Computing LISA clusters for access scores..."
    access_vals = Float64.(coalesce.(nd_df.access_score, 0.0))
    lisa_result = moran_local(access_vals, w; permutations=999, alpha=alpha)
    nd_df.lisa_cluster = lisa_result.cluster_type
    nd_df.lisa_p_value = lisa_result.p_values

    hh = count(==(:HH), lisa_result.cluster_type)
    ll = count(==(:LL), lisa_result.cluster_type)
    @info "LISA clusters: HH=$(hh) LL=$(ll)"

    # ── Spatial regression: access ~ poverty + uninsurance ───────────────────
    @info "Fitting spatial lag model: access ~ intercept + poverty + uninsurance..."
    poverty_vals    = Float64.(coalesce.(nd_df.poverty_pct,    5.0))
    uninsured_vals  = Float64.(coalesce.(nd_df.uninsured_pct, 10.0))
    X = hcat(ones(n), poverty_vals, uninsured_vals)
    y = access_vals

    # Normalise to improve convergence
    y_std = (y  .- mean(y))  ./ max(std(y), 1e-9)
    X_std = hcat(X[:, 1], (X[:, 2] .- mean(X[:, 2])) ./ max(std(X[:, 2]), 1e-9),
                           (X[:, 3] .- mean(X[:, 3])) ./ max(std(X[:, 3]), 1e-9))

    ols_result = lm_spatial(y_std, X_std, w;
                             coef_names=["intercept", "poverty", "uninsurance"])
    slm_result = slm(y_std, X_std, w;
                     coef_names=["intercept", "poverty", "uninsurance"])

    @info "OLS  AIC = $(round(ols_result.AIC; digits=1)), " *
          "LM-lag p = $(round(ols_result.lm_lag_p; digits=3)), " *
          "LM-err p = $(round(ols_result.lm_error_p; digits=3))"
    @info "SLM  ρ = $(round(slm_result.rho_or_lambda; digits=4)), " *
          "AIC = $(round(slm_result.AIC; digits=1))"

    # ── Save results ─────────────────────────────────────────────────────────
    out_cols = [:GEOID, :NAME, :centroid_lat, :centroid_lon,
                :access_score, :lisa_cluster, :lisa_p_value,
                :poverty_pct, :uninsured_pct, :total_pop]
    save_cols = filter(c -> hasproperty(nd_df, c), out_cols)
    CSV.write(joinpath(PROC_DIR, "nd_analysis_results.csv"),
              select(nd_df, save_cols))
    @info "Results saved to nd_analysis_results.csv"

    (; nd_df, w, moran_results, lisa=lisa_result, ols=ols_result, slm=slm_result)
end

# ── Run Phase 3 ───────────────────────────────────────────────────────────────
analysis_results = run_spatial_analysis(nd_df, prov_geocoded)
@info "Phase 3 (spatial analysis) complete."
