#!/usr/bin/env julia
# scripts/equity_dashboard.jl — Interactive health equity monitoring dashboard
# Chapter 48 — Open-Source Healthcare GIS Textbook in Julia
#
# Generates an equity monitoring report covering:
# - Demographic parity by county/region
# - Theil inequality decomposition (rural vs urban)
# - Concentration index against SES
# - Oaxaca-Blinder disparity decomposition
# - Group-specific calibration
# - Threshold recommendations

using Statistics, LinearAlgebra, Random, DataFrames, Printf

# Load HealthEquity from local path (fallback to synthetic demo)
const EQUITYPATH = joinpath(@__DIR__, "..", "packages", "HealthEquity")
const USE_PKG = isdir(EQUITYPATH)

if USE_PKG
    push!(LOAD_PATH, joinpath(EQUITYPATH, "src"))
    include(joinpath(EQUITYPATH, "src", "HealthEquity.jl"))
    using .HealthEquity
end

# ── Synthetic North Dakota equity dataset ─────────────────────────────────────

"""
    make_nd_equity_data(n_counties; rng) -> NamedTuple

Simulate healthcare access equity data for North Dakota-style counties.
Includes rural/urban classification, racial composition, poverty, and access scores.
"""
function make_nd_equity_data(n_counties::Int=53; rng=MersenneTwister(42))
    # Demographic mix
    pct_rural = clamp.(0.55 .+ 0.3*randn(rng, n_counties), 0.05, 0.99)
    pct_native = clamp.(0.02 .+ 0.15*rand(rng, n_counties).^2, 0.0, 0.99)
    poverty_rate = clamp.(0.12 .+ 0.08*randn(rng, n_counties), 0.02, 0.45)
    income_median = exp.(10.3 .+ 0.4*randn(rng, n_counties))  # log-normal
    uninsured_rate = clamp.(0.08 .+ 0.04*randn(rng, n_counties), 0.01, 0.35)

    # True access determinants
    access_true = 0.006 .- 0.003*pct_rural .- 0.004*poverty_rate .+
                  0.002*log.(income_median ./ 1e4) .- 0.003*uninsured_rate .+
                  0.0005*randn(rng, n_counties)
    access_true = max.(access_true, 0.0001)

    # Biased model predictions (underestimates rural access)
    noise_bias = -0.0008 .* pct_rural .+ 0.0004*randn(rng, n_counties)
    probs_raw  = clamp.(access_true ./ maximum(access_true) .+ noise_bias ./ maximum(access_true) .+
                        0.05*randn(rng, n_counties), 0.01, 0.99)

    # Binary: access deficit = 1 if in bottom quartile
    threshold_q = quantile(access_true, 0.25)
    y_access_deficit = Int.(access_true .< threshold_q)

    # Group: rural vs non-rural
    groups = [r > 0.6 ? "rural" : "urban" for r in pct_rural]

    DataFrame(
        county_id     = 1:n_counties,
        pct_rural     = pct_rural,
        pct_native    = pct_native,
        poverty_rate  = poverty_rate,
        income_median = income_median,
        uninsured_rate = uninsured_rate,
        access_score  = access_true,
        pred_probs    = probs_raw,
        y_deficit     = y_access_deficit,
        group         = groups,
        ses_rank      = (sortperm(sortperm(poverty_rate)) .- 0.5) ./ n_counties,
    )
end

# ── Dashboard sections ────────────────────────────────────────────────────────

function print_header(title::String)
    border = "═" ^ 60
    println("\n$border")
    println("  $title")
    println(border)
end

function run_equity_dashboard(df::DataFrame)
    n = nrow(df)
    println("\n" * "="^70)
    println("  HEALTHCARE ACCESS EQUITY DASHBOARD")
    println("  North Dakota County Analysis (n=$n counties)")
    println("="^70)

    groups   = df.group
    probs    = df.pred_probs
    y        = df.y_deficit
    ŷ        = Int.(probs .>= 0.5)
    ses_rank = df.ses_rank

    # ── 1. Group-level access comparison ──────────────────────────────────────
    print_header("1. Group Access Comparison")
    for g in sort(unique(groups))
        mask = groups .== g
        mean_access = mean(df.access_score[mask])
        mean_pred   = mean(probs[mask])
        deficit_pct = 100 * mean(y[mask])
        n_g = sum(mask)
        @printf("  %-8s  n=%2d  mean_access=%.4f  mean_pred=%.3f  deficit=%.0f%%\n",
                g, n_g, mean_access, mean_pred, deficit_pct)
    end

    # ── 2. Demographic parity ─────────────────────────────────────────────────
    print_header("2. Demographic Parity (DP gap ≤ 0.05 = fair)")
    dp = USE_PKG ? demographic_parity(ŷ, groups) :
         DataFrame(group_a=["rural"], group_b=["urban"],
                   dp_diff=[abs(mean(Float64.(ŷ[groups.=="rural"])) -
                               mean(Float64.(ŷ[groups.=="urban"])))],
                   fair_dp=[true])
    for row in eachrow(dp)
        status = row.dp_diff <= 0.05 ? "✓" : "✗"
        @printf("  %s vs %s: DP diff=%.3f %s\n",
                row.group_a, row.group_b, row.dp_diff, status)
    end

    # ── 3. Inequality indices ─────────────────────────────────────────────────
    print_header("3. Inequality Indices")
    gini = USE_PKG ? gini_coefficient(df.access_score) :
           begin
               x = sort(df.access_score)
               2*sum((1:n) .* x) / (n*sum(x)) - (n+1)/n
           end
    theil = USE_PKG ? theil_index(df.access_score) :
            begin
                μ = mean(df.access_score)
                mean(r > 0 ? r*log(r) : 0.0 for r in df.access_score ./ μ)
            end
    ci = USE_PKG ? concentration_index(df.access_score, df.poverty_rate) :
         2 * cov(df.access_score, ses_rank) / mean(df.access_score)

    @printf("  Gini:              %.4f  (0=equal, 1=maximal)\n", gini)
    @printf("  Theil T:           %.4f\n", theil)
    @printf("  Concentration idx: %.4f  (negative=pro-poor, positive=pro-rich)\n", ci)

    # ── 4. Equalized odds ─────────────────────────────────────────────────────
    print_header("4. Equalized Odds (TPR and FPR by group)")
    if USE_PKG
        eo = equalized_odds(ŷ, y, groups)
        for row in eachrow(eo)
            @printf("  %-8s  TPR=%.3f  FPR=%.3f  Acc=%.3f\n",
                    row.group, row.tpr, row.fpr, row.acc)
        end
    end

    # ── 5. Theil decomposition ────────────────────────────────────────────────
    print_header("5. Theil Between/Within Decomposition")
    if USE_PKG
        td = theil_decompose(df.access_score, groups)
        pct_B = td.total > 0 ? round(100*td.between/td.total; digits=1) : 0.0
        @printf("  Total Theil:   %.4f\n", td.total)
        @printf("  Between-group: %.4f (%s%%)\n", td.between, pct_B)
        @printf("  Within-group:  %.4f\n", td.within)
        @printf("  → %s%% of inequality is due to rural/urban group difference\n", pct_B)
    end

    # ── 6. Oaxaca-Blinder decomposition ───────────────────────────────────────
    print_header("6. Oaxaca-Blinder Gap Decomposition (rural vs urban)")
    if USE_PKG
        rural_mask = groups .== "rural"; urban_mask = groups .== "urban"
        X_feat = hcat(df.poverty_rate, df.uninsured_rate, df.pct_native)
        ob = oaxaca_blinder(
            X_feat[rural_mask, :], df.access_score[rural_mask],
            X_feat[urban_mask, :], df.access_score[urban_mask];
            feature_names=["poverty_rate", "uninsured_rate", "pct_native"]
        )
        @printf("  Total gap:    %.5f (rural - urban)\n", ob.total_gap)
        @printf("  Explained:    %.5f (%.1f%%)\n", ob.explained, ob.pct_explained)
        @printf("  Unexplained:  %.5f (%.1f%%)\n", ob.unexplained,
                100 - ob.pct_explained)
        println("  Feature breakdown:")
        for row in eachrow(ob.feature_contributions)
            @printf("    %-20s endow=%.5f  coef=%.5f\n",
                    row.feature, row.endowment, row.coefficient)
        end
    end

    # ── 7. Bias mitigation: threshold sweep ───────────────────────────────────
    print_header("7. Threshold Recommendations (equalise TPR)")
    if USE_PKG
        threshs = equalise_tpr(probs, y, groups)
        for (g, τ) in sort(collect(threshs))
            @printf("  Group %-8s → threshold = %.2f\n", g, τ)
        end
        ŷ_fair = apply_group_thresholds(probs, groups, threshs)
        eo_after = equalized_odds(ŷ_fair, y, groups)
        println("  After equalised-TPR thresholds:")
        for row in eachrow(eo_after)
            @printf("    %-8s  TPR=%.3f  FPR=%.3f\n", row.group, row.tpr, row.fpr)
        end
    end

    println("\n" * "="^70)
    println("  Dashboard complete.")
    println("="^70)
end

# ── Main ──────────────────────────────────────────────────────────────────────

function main()
    println("Generating synthetic North Dakota equity dataset...")
    df = make_nd_equity_data(53)
    run_equity_dashboard(df)
    return df
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
