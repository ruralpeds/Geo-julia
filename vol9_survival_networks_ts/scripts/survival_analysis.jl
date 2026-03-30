#!/usr/bin/env julia
# scripts/survival_analysis.jl
# North Dakota county healthcare survival analysis demonstration
# Models: time-to-readmission, time-to-treatment-access, competing risks

using Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "packages", "SurvivalAnalysis", "src", "SurvivalAnalysis.jl"))
using .SurvivalAnalysis

println("=" ^ 65)
println("  Vol 9 — Survival Analysis for Healthcare")
println("  North Dakota County Hospital Outcomes")
println("=" ^ 65)

# ── Simulated North Dakota county data ────────────────────────────────────────

function make_nd_survival_data(n=400; seed=42)
    rng = MersenneTwister(seed)

    # Patient characteristics
    age       = 45 .+ 25 .* rand(rng, n)
    poverty   = clamp.(0.10 .+ 0.15*randn(rng, n), 0.01, 0.50)
    rural     = rand(rng, n) .< 0.55        # 55% rural in ND
    comorbid  = rand(rng, n) .< 0.35

    # True hazard: rural, poverty, age increase readmission risk
    log_h = 0.3 .* (age .- 65)/20 .+ 0.8 .* poverty .+ 0.4 .* rural .+ 0.5 .* comorbid
    λ     = 0.02 .* exp.(log_h)

    # Simulate time-to-readmission (exponential)
    t_event = -log.(rand(rng, n)) ./ λ
    t_cens  = rand(rng, n) .* 300.0     # uniform censoring up to ~10 months
    obs     = min.(t_event, t_cens)
    status  = Int.(t_event .<= t_cens)

    # Competing risks: readmission (1) vs death (2)
    λ2      = 0.004 .* exp.(log_h .+ 0.2)  # death hazard
    t_death = -log.(rand(rng, n)) ./ λ2
    comp_status = zeros(Int, n)
    for i in 1:n
        t_min_comp = min(t_event[i], t_death[i], t_cens[i])
        obs[i]     = t_min_comp
        if t_event[i] <= t_death[i] && t_event[i] <= t_cens[i]
            comp_status[i] = 1
        elseif t_death[i] < t_event[i] && t_death[i] <= t_cens[i]
            comp_status[i] = 2
        end
    end

    X = hcat(age, poverty, Float64.(rural), Float64.(comorbid))
    groups = rural .? "rural" : "urban"

    (obs=obs, status=status, comp_status=comp_status,
     X=X, groups=groups, age=age, poverty=poverty,
     rural=rural, comorbid=comorbid, n=n)
end

d = make_nd_survival_data(400)

println("\n► Sample: N=$(d.n), Events=$(sum(d.status)), Competing=$(sum(d.comp_status.>0))")

# ── Section 1: Kaplan-Meier curves ────────────────────────────────────────────

println("\n[1] Kaplan-Meier Survival Estimates")
km_all   = kaplan_meier(d.obs, d.status)
km_rural = kaplan_meier(d.obs[d.rural],  d.status[d.rural])
km_urban = kaplan_meier(d.obs[.!d.rural], d.status[.!d.rural])

println("  Overall median survival:  $(round(km_all.median_survival,   digits=1)) days")
println("  Rural  median survival:   $(round(km_rural.median_survival,  digits=1)) days")
println("  Urban  median survival:   $(round(km_urban.median_survival,  digits=1)) days")
println("  Overall RMST (30d):       $(round(km_predict(km_all, 30.0),  digits=3))")

# ── Section 2: Log-rank test ──────────────────────────────────────────────────

println("\n[2] Log-rank Test: Rural vs Urban")
lr = logrank_test(d.obs, d.status, d.groups)
println("  χ²($(lr.df)) = $(round(lr.statistic, digits=3))  p = $(round(lr.p_value, digits=4))")
println("  Observed rural: $(round(lr.observed[1],digits=0))  Expected rural: $(round(lr.expected[1],digits=0))")
println("  Interpretation: $(lr.p_value < 0.05 ? "Significant difference (p<0.05)" : "No significant difference")")

# ── Section 3: Cox PH model ───────────────────────────────────────────────────

println("\n[3] Cox Proportional Hazards Model")
cox_m = cox_fit(d.obs, d.status, d.X;
                feature_names=["age","poverty","rural","comorbid"])
println("  $(lpad("Feature",12)) $(lpad("exp(β)",8)) $(lpad("SE",6)) $(lpad("p",8))")
println("  " * "-"^38)
for i in eachindex(cox_m.β)
    println("  $(lpad(cox_m.feature_names[i],12)) " *
            "$(lpad(round(exp(cox_m.β[i]),digits=3),8)) " *
            "$(lpad(round(cox_m.se[i],digits=3),6)) " *
            "$(lpad(round(cox_m.p_values[i],digits=4),8))")
end
println("  Concordance C: $(round(cox_m.concordance, digits=3))")
println("  Converged: $(cox_m.converged)")

# ── Section 4: Parametric AFT model ──────────────────────────────────────────

println("\n[4] Weibull AFT Model")
wbl_m = parametric_fit(d.obs, d.status, d.X;
                        dist=:weibull,
                        feature_names=["age","poverty","rural","comorbid"])
println("  Log-likelihood: $(round(wbl_m.log_lik, digits=1))")
println("  AIC: $(round(wbl_m.aic, digits=1))")
println("  log(scale): $(round(wbl_m.log_scale, digits=3))")

q  = parametric_predict(wbl_m, d.X[1:3,:])
println("  Median survival (first 3 patients): $(round.(q[:q50], digits=1))")

# ── Section 5: Competing risks CIF ────────────────────────────────────────────

println("\n[5] Cumulative Incidence Functions (Competing Risks)")
cif = cumulative_incidence(d.obs, d.comp_status)
t_eval = [30.0, 90.0, 180.0]
println("  Day  | CIF(readmission) | CIF(death)")
println("  " * "-"^40)
for t in t_eval
    c1 = round(cif_at(cif, 1, t) * 100, digits=1)
    c2 = round(cif_at(cif, 2, t) * 100, digits=1)
    println("  $(lpad(round(Int, t), 4)) | $(lpad(c1, 16))% | $(lpad(c2, 8))%")
end

# ── Section 6: Full report ────────────────────────────────────────────────────

println("\n[6] Survival Report")
report = survival_report(d.obs, d.status;
                          X=d.X, feature_names=["age","poverty","rural","comorbid"],
                          groups=d.groups, dist=:weibull,
                          model_name="ND-Readmission-Weibull")
println("  Concordance C: $(round(report.concordance, digits=3))")
println("  AIC (Weibull): $(round(report.aic, digits=1))")

println("\n✓ Survival analysis complete.")
