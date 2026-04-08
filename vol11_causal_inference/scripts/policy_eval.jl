#!/usr/bin/env julia
# scripts/policy_eval.jl
# DiD, synthetic control and RDD evaluation of ND rural health policy

using Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "packages", "PolicyEval", "src", "PolicyEval.jl"))
using .PolicyEval

println("=" ^ 65)
println("  Vol 11 — Policy Evaluation: ND Rural Health Initiative")
println("  DiD · Synthetic Control · Regression Discontinuity")
println("=" ^ 65)

# ── Data-generating processes ─────────────────────────────────────────────────

function make_did_panel(n_units=50, n_periods=10; seed=10, true_att=4.0)
    rng      = MersenneTwister(seed)
    treat_id = randperm(rng, n_units)[1:20]
    treat    = zeros(Bool, n_units)
    treat[treat_id] .= true
    treat_t  = 6  # policy enacted period 6

    y   = Float64[]; D = Bool[]; P = Bool[]; U = Int[]; T = Int[]
    for u in 1:n_units, t in 1:n_periods
        unit_fe = 2.0 * rand(rng)
        is_tr   = treat[u]; post = t >= treat_t
        eff     = is_tr && post ? true_att + 0.5*randn(rng) : 0.0
        push!(y, unit_fe + 0.2t + eff + 0.4*randn(rng))
        push!(D, is_tr); push!(P, post); push!(U, u); push!(T, t)
    end
    (y=y, treat=D, post=P, unit_ids=U, time=T, treat_t=treat_t,
     n_units=n_units, n_periods=n_periods)
end

function make_synth_panel(T_pre=12, T_post=6, n_donors=10; seed=20, true_effect=3.0)
    rng    = MersenneTwister(seed)
    # Donor outcomes ~ AR(1) with unit-specific mean
    donors = zeros(T_pre + T_post, n_donors)
    for j in 1:n_donors
        μⱼ = 4 + 2*rand(rng)
        donors[1,j] = μⱼ + randn(rng)*0.5
        for t in 2:T_pre+T_post
            donors[t,j] = 0.7*donors[t-1,j] + 0.3*μⱼ + randn(rng)*0.3
        end
    end
    # Treated = convex combination of first 3 donors (pre); + effect (post)
    w0  = [0.4, 0.35, 0.25, zeros(n_donors-3)...]
    y_t = donors * w0 .+ 0.1*randn(rng, T_pre+T_post)
    y_t[T_pre+1:end] .+= true_effect

    (Y_treated_pre=y_t[1:T_pre], Y_treated_post=y_t[T_pre+1:end],
     Y_donors_pre=donors[1:T_pre,:], Y_donors_post=donors[T_pre+1:end,:],
     true_effect=true_effect, T_pre=T_pre, T_post=T_post)
end

function make_rdd_panel(n=500; seed=30, true_tau=3.5, cutoff=0.0)
    rng = MersenneTwister(seed)
    # Running variable: county income index centred at eligibility threshold
    x   = randn(rng, n)
    # Counties below threshold get programme (x < 0 = eligible)
    # Outcome: health insurance coverage rate
    y   = -1.5.*x .+ true_tau .* (x .< cutoff) .+ 0.5.*randn(rng, n) .+ 7.0
    (y=y, x=x, cutoff=cutoff, true_tau=true_tau)
end

# ── Section 1: 2×2 DiD ───────────────────────────────────────────────────────

d1   = make_did_panel()
rng1 = MersenneTwister(1)
println("\n[1] 2×2 Difference-in-Differences")
println("  Panel: $(d1.n_units) units × $(d1.n_periods) periods  |  treat_t=$(d1.treat_t)")
dr = did_2x2(d1.y, d1.treat, d1.post; unit_ids=d1.unit_ids, n_boot=200, rng=rng1)
println("  DiD ATT: $(round(dr.β_did,digits=4)) ± $(round(dr.se,digits=4))")
println("  95% CI: [$(round(dr.ci_lower,digits=3)), $(round(dr.ci_upper,digits=3))]")
println("  True ATT = 4.0  |bias|=$(round(abs(dr.β_did - 4.0),digits=4))")

# ── Section 2: Parallel Trends Test ──────────────────────────────────────────

println("\n[2] Parallel Trends Pre-Test")
rng2 = MersenneTwister(2)
pt   = parallel_trends_test(d1.y, d1.treat, d1.time;
                              treat_time=d1.treat_t, unit_ids=d1.unit_ids,
                              n_boot=100, rng=rng2)
println("  Wald χ²($(pt.df)) = $(round(pt.chi2,digits=3))")
println("  p-value: $(round(pt.p_value,digits=4))")
println("  Parallel trends: $(pt.p_value > 0.05 ? "NOT rejected (p>0.05)" : "rejected")")

# ── Section 3: Event Study ────────────────────────────────────────────────────

println("\n[3] Event Study (TWFE)")
rng3 = MersenneTwister(3)
es   = event_study(d1.y, d1.treat, d1.time;
                   treat_time=d1.treat_t, unit_ids=d1.unit_ids, n_boot=100, rng=rng3)
println("  Relative periods: $(es.rel_periods)")
println("  β estimates:      $(round.(es.β, digits=3))")
println("  Pre-period (τ<0) max |β|: $(round(maximum(abs.(es.β[es.rel_periods .< 0])),digits=3))")
println("  Post-period τ=0 effect: $(round(es.β[es.rel_periods .== 0][1],digits=3))")

# ── Section 4: Staggered DiD ─────────────────────────────────────────────────

println("\n[4] Staggered DiD (Callaway-Sant'Anna type)")
rng4    = MersenneTwister(4)
n_u     = 30; n_t = 8
cohort  = fill(Inf, n_u)
cohort[1:10]  .= 4.0   # early adopters
cohort[11:20] .= 6.0   # late adopters
y_s = Float64[]; tc_s = Float64[]; time_s = Int[]
for u in 1:n_u, t in 1:n_t
    post = isfinite(cohort[u]) && t >= cohort[u]
    push!(y_s, post ? 3.0 + 0.3*randn(rng4) : 0.1t + 0.3*randn(rng4))
    push!(tc_s, cohort[u]); push!(time_s, t)
end
sd = staggered_did(y_s, tc_s, time_s; n_boot=100, rng=rng4)
println("  Cohorts: $(sd.n_cohorts)  aggregate ATT: $(round(sd.att_agg,digits=4))")

# ── Section 5: Synthetic Control ─────────────────────────────────────────────

d2  = make_synth_panel()
println("\n[5] Synthetic Control (Abadie et al. 2010)")
println("  T_pre=$(d2.T_pre)  T_post=$(d2.T_post)  $(size(d2.Y_donors_pre,2)) donor units")
sr  = synth_control(d2.Y_treated_pre, d2.Y_donors_pre,
                    d2.Y_treated_post, d2.Y_donors_post; n_placebo_iter=8)
println("  Optimal donor weights (top 3): $(round.(sort(sr.weights,rev=true)[1:3],digits=3))")
println("  Pre-treatment RMSPE: $(round(sr.rmspe_pre,digits=4))")
println("  Post-treatment RMSPE: $(round(sr.rmspe_post,digits=4))")
println("  RMSPE ratio: $(round(sr.ratio,digits=3))")

pl = synth_placebo(sr)
println("  Placebo p-value: $(round(pl.p_value,digits=4))")
println("  Treated rank: $(pl.rank)/$(pl.n_donors+1)")

gaps = synth_gaps(d2.Y_treated_post, d2.Y_donors_post, sr.weights)
println("  Mean post-gap: $(round(mean(gaps),digits=4))  true effect=$(d2.true_effect)")

# ── Section 6: Regression Discontinuity ──────────────────────────────────────

d3   = make_rdd_panel()
rng6 = MersenneTwister(6)
println("\n[6] Regression Discontinuity Design")
println("  n=$(length(d3.y))  cutoff=$(d3.cutoff)  true τ=$(d3.true_tau)")

rdd1 = rdd_fit(d3.y, d3.x; cutoff=d3.cutoff, poly_order=1, n_boot=200, rng=rng6)
rdd2 = rdd_fit(d3.y, d3.x; cutoff=d3.cutoff, poly_order=2, n_boot=200, rng=rng6)

println("  Linear RDD:")
println("    τ̂=$(round(rdd1.τ,digits=4)) ± $(round(rdd1.se,digits=4))")
println("    Bandwidth: $(round(rdd1.bandwidth,digits=4))")
println("    N left=$(rdd1.n_left)  N right=$(rdd1.n_right)")
println("  Quadratic RDD:")
println("    τ̂=$(round(rdd2.τ,digits=4)) ± $(round(rdd2.se,digits=4))")

mc = mccrary_test(d3.x; cutoff=d3.cutoff)
println("  McCrary density test: z=$(round(mc.z,digits=3))  p=$(round(mc.p_value,digits=4))")
println("  $(mc.p_value > 0.05 ? "No evidence of sorting (p>0.05)" : "Potential sorting detected")")

# ── Section 7: Policy Report ─────────────────────────────────────────────────

println("\n[7] Policy Evaluation Summary")
rpt = policy_report(study_name="ND Rural Health Initiative";
                    did_result=dr, synth_result=sr, rdd_result=rdd1)
print_policy_report(rpt)

println("\n✓ Policy evaluation pipeline complete.")
