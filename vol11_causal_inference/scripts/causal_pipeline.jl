#!/usr/bin/env julia
# scripts/causal_pipeline.jl
# Propensity score methods for evaluating ND rural healthcare access programme

using Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "packages", "CausalInference", "src", "CausalInference.jl"))
using .CausalInference

println("=" ^ 65)
println("  Vol 11 — Causal Inference: ND Healthcare Access Programme")
println("  PS Estimation · IPW · AIPW · Overlap · Matching")
println("=" ^ 65)

# ── Simulated observational study ─────────────────────────────────────────────

function make_nd_obs_study(n=400; seed=42, true_ate=2.5)
    rng   = MersenneTwister(seed)
    # Covariates: county rurality, poverty rate, elderly fraction, distance
    X = hcat(rand(rng, n),          # rurality 0-1 (rural = more likely treated)
             rand(rng, n) .* 0.3,   # poverty rate
             rand(rng, n) .* 0.25,  # elderly fraction
             rand(rng, n) .* 100)   # distance to nearest clinic (km)
    X[:,4] ./= 100.0  # normalise to [0,1]

    # True PS: rural + poor counties more likely to receive intervention
    log_odds = 0.5 .+ 1.2*X[:,1] .+ 0.8*X[:,2] .- 0.5*X[:,4]
    ps_true  = 1 ./ (1 .+ exp.(-log_odds))
    D        = Float64.(rand(rng, n) .< ps_true)

    # Outcome: health access score 0-10 (higher = better)
    # Confounders affect both D and y
    y = 4.0 .+ true_ate.*D .+ 1.5.*X[:,1] .- 2.0.*X[:,2] .+
        0.5.*X[:,3] .- 0.8.*X[:,4] .+ randn(rng, n)
    y = clamp.(y, 0, 10)

    fnames = ["rurality","poverty","elderly","distance"]
    (X=X, D=D, y=y, ps_true=ps_true, fnames=fnames, true_ate=true_ate)
end

data = make_nd_obs_study()
println("\n► N=$(size(data.X,1))  Treated=$(Int(sum(data.D)))  Control=$(Int(sum(1 .- data.D)))")
println("  True ATE: $(data.true_ate)")

# ── Section 1: Propensity Score Estimation ────────────────────────────────────

println("\n[1] Propensity Score Model (Logistic Regression)")
rng1   = MersenneTwister(1)
ps_mod = ps_fit(data.D, data.X; feature_names=data.fnames)
println("  Converged: $(ps_mod.converged)  Iterations: $(ps_mod.n_iter)")
println("  Log-likelihood: $(round(ps_mod.log_lik, digits=2))")

p̂ = ps_predict(ps_mod, data.X)
println("  PS range: [$(round(minimum(p̂),digits=3)), $(round(maximum(p̂),digits=3))]")
println("  PS mean (treated):  $(round(mean(p̂[data.D .== 1]),digits=3))")
println("  PS mean (control):  $(round(mean(p̂[data.D .== 0]),digits=3))")

ov = ps_overlap(p̂, data.D)
println("  Overlap region: [$(round(ov.overlap_min,digits=3)), $(round(ov.overlap_max,digits=3))]")
println("  Effective N treated: $(round(ov.eff_n_treated,digits=1))")
println("  Effective N control: $(round(ov.eff_n_control,digits=1))")

# ── Section 2: Common Support Trimming ────────────────────────────────────────

println("\n[2] Common Support Trimming (PS ∈ [0.05, 0.95])")
ps_t, D_t, y_t, idx = ps_trim(p̂, data.D, data.y)
X_t = data.X[idx, :]
println("  Observations retained: $(length(idx))/$(size(data.X,1))")
println("  Trimmed treated: $(Int(sum(D_t .== 1)))  control: $(Int(sum(D_t .== 0)))")

# ── Section 3: IPW Estimators ─────────────────────────────────────────────────

println("\n[3] IPW ATE Estimators")
rng3 = MersenneTwister(3)
res_ht  = ipw_ate(D_t, y_t, ps_t; estimator=:ht,    n_boot=200, rng=rng3)
res_hj  = ipw_ate(D_t, y_t, ps_t; estimator=:hajek, n_boot=200, rng=rng3)
println("  HT  ATE: $(round(res_ht.ate,digits=4)) ± $(round(res_ht.se,digits=4))  95%CI=[$(round(res_ht.ci_lower,digits=3)),$(round(res_ht.ci_upper,digits=3))]")
println("  Hajek ATE: $(round(res_hj.ate,digits=4)) ± $(round(res_hj.se,digits=4))  95%CI=[$(round(res_hj.ci_lower,digits=3)),$(round(res_hj.ci_upper,digits=3))]")

# ── Section 4: AIPW (doubly robust) ──────────────────────────────────────────

println("\n[4] AIPW Doubly-Robust ATE")
rng4  = MersenneTwister(4)
res_dr = aipw_ate(D_t, y_t, ps_t, X_t; n_boot=200, rng=rng4)
println("  AIPW ATE: $(round(res_dr.ate,digits=4)) ± $(round(res_dr.se,digits=4))")
println("  95% CI: [$(round(res_dr.ci_lower,digits=3)), $(round(res_dr.ci_upper,digits=3))]")
println("  True ATE: $(data.true_ate)  Bias: $(round(abs(res_dr.ate - data.true_ate),digits=4))")

# ── Section 5: Overlap Weights ────────────────────────────────────────────────

println("\n[5] Overlap-Weighted ATE (Li et al. 2018)")
rng5   = MersenneTwister(5)
res_ov = overlap_ate(D_t, y_t, ps_t; n_boot=200, rng=rng5)
println("  Overlap ATE: $(round(res_ov.ate,digits=4)) ± $(round(res_ov.se,digits=4))")

# ── Section 6: Nearest-Neighbour Matching ─────────────────────────────────────

println("\n[6] Nearest-Neighbour PS Matching (ATT)")
rng6 = MersenneTwister(6)
mr   = nn_match(D_t, y_t, ps_t, X_t; k=1, n_boot=200, rng=rng6)
println("  Matched pairs: $(mr.n_matched)")
println("  ATT: $(round(mr.att,digits=4)) ± $(round(mr.se,digits=4))")
println("  95% CI: [$(round(mr.ci_lower,digits=3)), $(round(mr.ci_upper,digits=3))]")

tbl = balance_table(mr, data.fnames)
println("  Balance:")
for row in tbl
    println("    $(lpad(row.covariate,12)): SMD before=$(round(row.smd_before,digits=3))  after=$(round(row.smd_after,digits=3))  $(row.improved ? "✓" : "✗")")
end

# ── Section 7: Estimator comparison ──────────────────────────────────────────

println("\n[7] Estimator Comparison")
println("  True ATE = $(data.true_ate)")
for (name, est, se) in [("HT",     res_ht.ate,  res_ht.se),
                         ("Hajek",  res_hj.ate,  res_hj.se),
                         ("AIPW",   res_dr.ate,  res_dr.se),
                         ("Overlap",res_ov.ate,  res_ov.se),
                         ("PS-Match ATT",mr.att,  mr.se)]
    bias = round(abs(est - data.true_ate), digits=4)
    println("  $(lpad(name,14)): $(round(est,digits=4)) ± $(round(se,digits=4))  |bias|=$(bias)")
end

# ── Section 8: Full report ────────────────────────────────────────────────────

println("\n[8] Full Causal Report")
rng8 = MersenneTwister(8)
rpt  = causal_report(data.D, data.y, data.X;
                     study_name="ND Healthcare Access",
                     feature_names=data.fnames, n_boot=100, rng=rng8)
print_causal_report(rpt)

println("\n✓ Causal inference pipeline complete.")
