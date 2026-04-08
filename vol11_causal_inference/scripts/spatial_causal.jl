#!/usr/bin/env julia
# scripts/spatial_causal.jl
# Spatial causal inference for ND rural health facility expansion

using Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "packages", "SpatialCausal", "src", "SpatialCausal.jl"))
using .SpatialCausal

println("=" ^ 65)
println("  Vol 11 — Spatial Causal Inference: ND Facility Expansion")
println("  Spatial DiD · Conley SE · Geographic IV")
println("=" ^ 65)

# ── Simulated ND county panel ─────────────────────────────────────────────────

function make_nd_panel(n_units=60, n_periods=8; seed=42,
                       true_direct=5.0, true_spill=1.8)
    rng     = MersenneTwister(seed)
    # Counties spread across ND [0,10]×[0,4]
    coords  = hcat(rand(rng, n_units) .* 10, rand(rng, n_units) .* 4)
    # 3 new clinic sites opened at period 5
    treat_sites = [2.0 1.0; 5.5 3.0; 8.5 1.5]
    treat_t = 5

    y_all   = Float64[]
    uid_all = Int[]
    post_all = Bool[]

    for u in 1:n_units
        d_min = minimum(sqrt(sum((coords[u,:] .- treat_sites[k,:]).^2))
                        for k in 1:size(treat_sites,1))
        is_t  = d_min <= 1.5
        is_s  = !is_t && d_min <= 2.8
        unit_fe = 3.0*rand(rng)
        for t in 1:n_periods
            post = t >= treat_t
            eff  = post && is_t ? true_direct : 0.0
            spe  = post && is_s ? true_spill  : 0.0
            noise = 0.3*randn(rng)
            push!(y_all, unit_fe + 0.3t + eff + spe + noise)
            push!(uid_all, u); push!(post_all, post)
        end
    end

    (y=y_all, coords=coords, post=post_all, unit_ids=uid_all,
     treatment_sites=treat_sites, n_units=n_units,
     true_direct=true_direct, true_spill=true_spill)
end

function make_ols_spatial(n=120; seed=43)
    rng    = MersenneTwister(seed)
    coords = hcat(rand(rng, n) .* 8, rand(rng, n) .* 4)
    X      = hcat(rand(rng, n), randn(rng, n))   # covariates
    β_true = [1.5, -0.8]
    # Spatially correlated error (Moran-like): ε ∝ distance to centre
    spatial_comp = 0.6 .* (coords[:,1] .- 4.0) ./ 4.0
    ε  = spatial_comp .+ 0.4.*randn(rng, n)
    y  = X * β_true .+ ε
    (y=y, X=X, coords=coords)
end

function make_iv_spatial(n=250; seed=44, true_tau=6.0)
    rng  = MersenneTwister(seed)
    # County centroid locations
    coords = hcat(rand(rng, n) .* 10, rand(rng, n) .* 4)
    # Historical (pre-policy) clinic locations as instrument
    hist_clinics = [1.5 0.5; 4.0 3.5; 7.5 2.0; 9.0 0.5]
    # IV: distance-based access to historical clinics
    Z  = [mean(1.0 ./ (1.0 .+ [sqrt(sum((coords[i,:] .- hist_clinics[k,:]).^2))
                                for k in 1:size(hist_clinics,1)])) for i in 1:n]
    # Confounders: urban density, income
    X   = hcat(rand(rng, n), rand(rng, n) .* 0.4)
    # Endogenous treatment: current access (higher near clinics)
    D   = Z .+ 0.5*X[:,1] .+ 0.2*randn(rng, n)
    # Outcome: insurance coverage rate
    U   = 0.3*randn(rng, n)  # unobserved confounder correlated with D
    y   = true_tau.*D .+ 2.0.*X[:,1] .- 1.5.*X[:,2] .+ 0.8.*U .+ randn(rng, n)
    fnames = ["urban_density", "income"]
    (y=y, D=D, Z=Z, X=X, coords=coords, true_tau=true_tau, fnames=fnames)
end

nd = make_nd_panel()
println("\n► $(nd.n_units) ND counties × 8 periods = $(length(nd.y)) observations")
println("  Treatment sites: $(size(nd.treatment_sites,1))")
println("  True direct effect: $(nd.true_direct)  Spillover: $(nd.true_spill)")

# ── Section 1: Spatial DiD ────────────────────────────────────────────────────

println("\n[1] Spatial DiD with Spillover Zones")
rng1 = MersenneTwister(1)
sdr  = spatial_did(nd.y, nd.coords, nd.post, nd.treatment_sites;
                   radius=1.5, buffer=1.3, unit_ids=nd.unit_ids,
                   n_boot=200, rng=rng1)

println("  Treatment zone (r≤1.5): $(sdr.n_treated) units")
println("  Spillover zone (1.5<r≤2.8): $(sdr.n_spillover) units")
println("  Pure control: $(sdr.n_control) units")
println()
println("  Direct effect τ̂: $(round(sdr.β_direct,digits=4)) ± $(round(sdr.se_direct,digits=4))")
println("  95% CI: [$(round(sdr.ci_direct[1],digits=3)), $(round(sdr.ci_direct[2],digits=3))]")
println("  True τ: $(nd.true_direct)  Bias: $(round(abs(sdr.β_direct-nd.true_direct),digits=4))")
println()
println("  Spillover φ̂: $(round(sdr.β_spillover,digits=4)) ± $(round(sdr.se_spillover,digits=4))")
println("  95% CI: [$(round(sdr.ci_spillover[1],digits=3)), $(round(sdr.ci_spillover[2],digits=3))]")
println("  True φ: $(nd.true_spill)  Bias: $(round(abs(sdr.β_spillover-nd.true_spill),digits=4))")

sd = spillover_decomposition(sdr)
println("  Spillover/Direct ratio: $(round(sd.ratio,digits=3))")

# ── Section 2: Conley Spatial HAC Standard Errors ─────────────────────────────

println("\n[2] Conley Spatial HAC Standard Errors")
ol = make_ols_spatial()
cr  = conley_se(ol.y, ol.X, ol.coords; cutoff=2.0,
                feature_names=["land_use","elevation"])
println("  Spatial bandwidth: $(round(cr.cutoff,digits=4))")
println("  n=$(cr.n)")
println()
println("  Covariate comparison (OLS SE vs Conley SE):")
for j in 1:length(cr.β)
    nm  = cr.feature_names[j]
    inf = cr.se_conley[j] / max(cr.se_ols[j], 1e-10)
    println("    $(lpad(nm,15)): β=$(round(cr.β[j],digits=4))  OLS SE=$(round(cr.se_ols[j],digits=4))  Conley SE=$(round(cr.se_conley[j],digits=4))  inflation=$(round(inf,digits=2))×")
end

# Auto-bandwidth
cr_auto = conley_se(ol.y, ol.X, ol.coords;
                    feature_names=["land_use","elevation"])
println("  Auto-bandwidth: $(round(cr_auto.cutoff,digits=4))")

# ── Section 3: Geographic Instrumental Variables ──────────────────────────────

println("\n[3] Geographic IV (Historical Clinic Locations)")
iv  = make_iv_spatial()
println("  n=$(length(iv.y))  True τ=$(iv.true_tau)")
println("  IV: mean inverse-distance to 4 historical clinics")
gr  = geo_iv_2sls(iv.y, iv.D, iv.Z, iv.X;
                  feature_names=iv.fnames, instrument_name="hist_clinic_access")
wt  = weak_instrument_test(gr)
println()
println("  First stage:")
println("    R² = $(round(gr.r2_first,digits=3))")
println("    F-stat = $(round(gr.f_stat,digits=2))")
println("    Weak instrument: $(wt.weak ? "YES ⚠" : "NO ✓")")
println()
println("  2SLS estimates:")
for j in 1:length(gr.β_2sls)
    nm = gr.feature_names[j]
    t  = gr.β_2sls[j] / max(gr.se_2sls[j], 1e-10)
    p  = 2*(1 - 0.5*(1 + tanh(t*0.6))) |> abs  # rough p
    println("    $(lpad(nm,20)): β=$(round(gr.β_2sls[j],digits=4))  SE=$(round(gr.se_2sls[j],digits=4))")
end
println("  True τ=$(iv.true_tau)  2SLS τ̂=$(round(gr.β_2sls[2],digits=4))")

iv_summary(gr)

# ── Section 4: OLS vs 2SLS comparison ────────────────────────────────────────

println("\n[4] OLS vs 2SLS Comparison")
# Naive OLS (ignores endogeneity)
Xd_ols = hcat(ones(length(iv.y)), iv.D, iv.X)
β_ols  = (Xd_ols'Xd_ols + 1e-10*I) \ (Xd_ols' * iv.y)
println("  OLS τ̂:   $(round(β_ols[2],digits=4))  (biased due to endogeneity)")
println("  2SLS τ̂:  $(round(gr.β_2sls[2],digits=4))  (consistent)")
println("  True τ:  $(iv.true_tau)")
println("  OLS bias: $(round(abs(β_ols[2]-iv.true_tau),digits=4))")
println("  2SLS bias:$(round(abs(gr.β_2sls[2]-iv.true_tau),digits=4))")

# ── Section 5: Summary report ─────────────────────────────────────────────────

println("\n[5] Spatial Causal Inference Report")
rpt = spatial_causal_report(study_name="ND Facility Expansion";
                             spatial_did_result=sdr, conley_result=cr, geo_iv_result=gr)
print_spatial_causal_report(rpt)

println("\n✓ Spatial causal inference pipeline complete.")
