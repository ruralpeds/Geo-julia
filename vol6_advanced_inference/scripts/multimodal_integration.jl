#!/usr/bin/env julia
# scripts/multimodal_integration.jl
# Multi-modal data integration: EHR claims + geospatial + provider network
# Chapter 47 — Julia Healthcare GIS Textbook, Vol 6
#
# Three data modalities:
#   (1) Geospatial: county-level access scores, demographics (E2SFCA)
#   (2) Claims/EHR: utilisation rates, diagnoses, costs (synthetic APCD)
#   (3) Network: provider referral graph (centrality, community)
#
# Integration strategy: Feature-level fusion → joint ML model

using DataFrames, Statistics, LinearAlgebra, Random

# ── Synthetic multi-modal dataset generator ───────────────────────────────────

"""
    generate_multimodal_dataset(n_counties=53; seed=42) -> NamedTuple

Generate synthetic three-modality healthcare dataset.
Returns: (geo_df, claims_df, network_df, target_df)
"""
function generate_multimodal_dataset(n_counties::Int = 53; seed::Int = 42)
    rng = MersenneTwister(seed)

    geoids = ["38" * lpad(i, 3, '0') for i in 1:n_counties]

    # ── Modality 1: Geospatial features ──────────────────────────────────────
    geo_df = DataFrame(
        GEOID         = geoids,
        lat           = 46.5 .+ randn(rng, n_counties) .* 1.5,
        lon           = -100.5 .+ randn(rng, n_counties) .* 2.0,
        access_e2sfca = abs.(randn(rng, n_counties)) .* 0.008 .+ 0.003,
        moran_local   = randn(rng, n_counties) .* 0.3,
        rurality_idx  = clamp.(rand(rng, n_counties), 0, 1),
        poverty_pct   = clamp.(10.0 .+ 8.0 .* randn(rng, n_counties), 2, 35),
        uninsured_pct = clamp.(12.0 .+ 6.0 .* randn(rng, n_counties), 1, 30),
        pop_density   = exp.(2.0 .+ 1.5 .* randn(rng, n_counties)),   # per km²
    )

    # ── Modality 2: Claims / EHR features ────────────────────────────────────
    claims_df = DataFrame(
        GEOID              = geoids,
        # Utilisation
        ed_visits_per_1k   = abs.(randn(rng, n_counties)) .* 100 .+ 300,
        pcp_visits_per_1k  = abs.(randn(rng, n_counties)) .* 200 .+ 500,
        hosp_admissions_1k = abs.(randn(rng, n_counties)) .* 30  .+ 80,
        # Preventable conditions (AHRQ PQI)
        pqi_diabetes_pct   = clamp.(5 .+ 3 .* randn(rng, n_counties), 1, 15),
        pqi_chf_pct        = clamp.(3 .+ 2 .* randn(rng, n_counties), 0.5, 10),
        pqi_copd_pct       = clamp.(4 .+ 2 .* randn(rng, n_counties), 0.5, 12),
        # Costs
        avg_cost_per_member = abs.(randn(rng, n_counties)) .* 500 .+ 4500,
        # Chronic disease prevalence
        diabetes_prev_pct   = clamp.(10 .+ 5 .* randn(rng, n_counties), 3, 25),
        hypertension_prev_pct = clamp.(35 .+ 8 .* randn(rng, n_counties), 15, 60),
        # Telehealth
        telehealth_pct_visits = clamp.(15 .+ 8 .* randn(rng, n_counties), 2, 40),
    )

    # ── Modality 3: Provider network features ─────────────────────────────────
    # Per-county network metrics (aggregated from referral graph)
    network_df = DataFrame(
        GEOID                = geoids,
        n_providers          = round.(Int, abs.(randn(rng, n_counties)) .* 20 .+ 5),
        pagerank_mean        = abs.(randn(rng, n_counties)) .* 0.01 .+ 0.005,
        betweenness_mean     = rand(rng, n_counties) .* 0.3,
        community_id         = rand(rng, 1:6, n_counties),   # network community
        hhi_referral         = clamp.(0.15 .+ 0.15 .* randn(rng, n_counties), 0.05, 0.9),
        isolation_idx        = clamp.(0.3 .+ 0.2 .* randn(rng, n_counties), 0, 1),
        avg_path_length      = clamp.(3.0 .+ randn(rng, n_counties), 1.5, 8.0),
    )

    # ── Target: preventable hospitalisation rate (outcome) ────────────────────
    # True data-generating process (DGP): mix of all three modalities
    target = @. 100 +
        -200 * geo_df.access_e2sfca +          # better access → fewer admissions
         0.5 * geo_df.poverty_pct +             # poverty increases risk
         0.3 * claims_df.pqi_diabetes_pct +     # PQI indicator
        -0.1 * network_df.pagerank_mean * 1000 + # network connectivity helps
         10  * randn(rng, n_counties)            # noise

    target_df = DataFrame(GEOID=geoids, prev_hosp_rate=max.(target, 10.0))

    (geo=geo_df, claims=claims_df, network=network_df, target=target_df)
end

# ── Feature fusion ────────────────────────────────────────────────────────────

"""
    fuse_modalities(geo_df, claims_df, network_df) -> DataFrame

Horizontally join all three modalities on GEOID.
Adds cross-modal interaction features:
  - access × pqi_diabetes  (access modifies diabetes risk)
  - hhi × betweenness      (network concentration × centrality)
  - telehealth × rurality  (telehealth impact in rural areas)
"""
function fuse_modalities(geo_df    ::DataFrame,
                          claims_df ::DataFrame,
                          network_df::DataFrame)::DataFrame
    # Join on GEOID
    df = innerjoin(geo_df, claims_df;    on=:GEOID)
    df = innerjoin(df,     network_df;   on=:GEOID)

    # Cross-modal interaction features
    df[!, :access_x_diabetes]    = df.access_e2sfca .* df.pqi_diabetes_pct
    df[!, :hhi_x_betweenness]    = df.hhi_referral  .* df.betweenness_mean
    df[!, :telehealth_x_rural]   = df.telehealth_pct_visits .* df.rurality_idx
    df[!, :pcp_x_access]         = df.pcp_visits_per_1k .* df.access_e2sfca
    df[!, :network_x_pqi]        = df.pagerank_mean .* df.pqi_diabetes_pct

    df
end

# ── Modality importance analysis ──────────────────────────────────────────────

"""
    modality_importance(X_full, y, feature_groups; n_perms=50) -> DataFrame

Permutation importance at the modality level.
For each modality M, permute all features in M and measure RMSE increase.
"""
function modality_importance(X_full       ::Matrix{Float64},
                              y            ::Vector{Float64},
                              feature_groups::Dict{String,Vector{Int}};
                              n_perms      ::Int = 50,
                              rng          ::AbstractRNG = MersenneTwister(42))

    # Fit simple linear model for baseline
    β_base  = (X_full'X_full + 1e-6I) \ (X_full'y)
    ŷ_base  = X_full * β_base
    rmse_base = sqrt(mean((y .- ŷ_base).^2))

    results = NamedTuple[]
    for (group_name, feat_idx) in feature_groups
        delta_rmse = zeros(n_perms)
        for k in 1:n_perms
            X_perm = copy(X_full)
            for j in feat_idx
                X_perm[:, j] = X_perm[randperm(rng, size(X_full,1)), j]
            end
            ŷ_perm = X_perm * β_base
            delta_rmse[k] = sqrt(mean((y .- ŷ_perm).^2)) - rmse_base
        end
        push!(results, (modality=group_name,
                        importance_mean=mean(delta_rmse),
                        importance_std=std(delta_rmse),
                        n_features=length(feat_idx)))
    end
    sort!(DataFrame(results), :importance_mean; rev=true)
end

# ── Missing modality imputation ───────────────────────────────────────────────

"""
    impute_missing_modality(df_complete, df_partial, shared_features, target_features)
                           -> DataFrame

When a county has no claims data, impute from the geospatial + network modalities
via nearest-neighbour imputation (Euclidean on shared feature space).
"""
function impute_missing_modality(df_complete    ::DataFrame,
                                  df_partial     ::DataFrame,
                                  shared_features::Vector{Symbol},
                                  target_features::Vector{Symbol})::DataFrame
    n_comp = nrow(df_complete)
    n_part = nrow(df_partial)

    X_ref = Matrix(df_complete[!, shared_features] .|> Float64)
    X_new = Matrix(df_partial[!, shared_features]  .|> Float64)

    # Standardise
    μ = mean(X_ref; dims=1)
    σ = max.(std(X_ref; dims=1), 1e-9)
    X_ref_s = (X_ref .- μ) ./ σ
    X_new_s = (X_new .- μ) ./ σ

    result = copy(df_partial)
    for col in target_features
        result[!, col] = zeros(n_part)
    end

    for i in 1:n_part
        dists = [norm(X_ref_s[j,:] .- X_new_s[i,:]) for j in 1:n_comp]
        nn_idx = argmin(dists)
        for col in target_features
            result[i, col] = df_complete[nn_idx, col]
        end
    end
    result
end

# ── Uncertainty-aware fusion ──────────────────────────────────────────────────

"""
    bayesian_model_averaging(predictions, variances, weights=nothing) -> (mean, var)

Bayesian Model Averaging across predictions from different modality-specific models.
Weights default to inverse variance (precision weighting).
"""
function bayesian_model_averaging(predictions::Vector{Vector{Float64}},
                                   variances   ::Vector{Vector{Float64}},
                                   weights     ::Union{Vector{Float64},Nothing} = nothing)
    K = length(predictions)
    n = length(predictions[1])
    prec = [1.0 ./ max.(v, 1e-12) for v in variances]

    if isnothing(weights)
        # Precision-weighted average
        total_prec = sum(prec)
        weights_use = [prec[k] ./ total_prec for k in 1:K]
    else
        w_norm = weights ./ sum(weights)
        weights_use = [fill(w_norm[k], n) for k in 1:K]
    end

    μ_bma  = sum(weights_use[k] .* predictions[k] for k in 1:K)
    # BMA variance: Σₖ wₖ(σₖ² + μₖ²) - μ_bma²
    var_bma = sum(weights_use[k] .* (variances[k] .+ predictions[k].^2) for k in 1:K) .-
              μ_bma.^2
    (mean=μ_bma, var=max.(var_bma, 0.0))
end

# ── Demo ──────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__
    @info "Multi-modal Integration Demo — Chapter 47"

    data = generate_multimodal_dataset(53)
    @info "Generated: $(nrow(data.geo)) geo, $(nrow(data.claims)) claims, $(nrow(data.network)) network records"

    # Fuse modalities
    fused = fuse_modalities(data.geo, data.claims, data.network)
    @info "Fused dataset: $(ncol(fused)) features, $(nrow(fused)) counties"

    # Target
    y = Float64.(data.target.prev_hosp_rate)

    # Prepare feature groups
    geo_cols     = [:access_e2sfca, :moran_local, :rurality_idx, :poverty_pct, :uninsured_pct]
    claims_cols  = [:pqi_diabetes_pct, :pqi_chf_pct, :ed_visits_per_1k, :diabetes_prev_pct]
    network_cols = [:pagerank_mean, :betweenness_mean, :hhi_referral]
    all_cols     = vcat(geo_cols, claims_cols, network_cols)

    X = Matrix(fused[!, all_cols] .|> Float64)
    feat_groups = Dict(
        "geospatial" => 1:length(geo_cols),
        "claims"     => length(geo_cols)+1 : length(geo_cols)+length(claims_cols),
        "network"    => length(geo_cols)+length(claims_cols)+1 : length(all_cols),
    )

    # Modality importance
    imp = modality_importance(X, y, feat_groups)
    @info "Modality importance ranking:"
    for row in eachrow(imp)
        @info "  $(row.modality): Δ RMSE = $(round(row.importance_mean; digits=3)) ± $(round(row.importance_std; digits=3))"
    end

    # BMA demo
    preds = [X[:, 1:5] * randn(5) .+ 100 for _ in 1:3]
    vars  = [abs.(randn(53)) .* 50 .+ 10 for _ in 1:3]
    μ_bma, v_bma = bayesian_model_averaging(preds, vars)
    @info "BMA mean range: [$(round(minimum(μ_bma);digits=1)), $(round(maximum(μ_bma);digits=1))]"

    @info "Chapter 47 demo complete"
end
