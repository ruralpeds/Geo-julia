#!/usr/bin/env julia
# scripts/network_epidemic.jl
# Healthcare facility network analysis + epidemic modelling for North Dakota

using Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "packages", "NetworkHealth", "src", "NetworkHealth.jl"))
using .NetworkHealth

println("=" ^ 65)
println("  Vol 9 — Healthcare Networks & Epidemic Modelling")
println("  North Dakota Facility Network Analysis")
println("=" ^ 65)

# ── Simulated ND facility network ─────────────────────────────────────────────

function make_nd_facility_data(; seed=7)
    rng = MersenneTwister(seed)

    # 12 facilities: 3 regional hospitals, 5 critical access hospitals, 4 clinics
    names = ["Bismarck-RH", "Fargo-RH", "GrandForks-RH",
             "Minot-CAH", "Dickinson-CAH", "Jamestown-CAH", "Williston-CAH", "Devils-Lake-CAH",
             "Mandan-Clinic", "West-Fargo-Clinic", "Wahpeton-Clinic", "Valley-City-Clinic"]
    types = vcat(fill("regional", 3), fill("cah", 5), fill("clinic", 4))
    n     = length(names)

    # Patient flow matrix (transfers/month)
    F = zeros(n, n)
    # Clinics → CAH → Regional hospitals
    for i in 9:12; F[i, rand(rng, 4:8)] += rand(rng) * 30; end   # clinics refer to CAH
    for i in 4:8;  F[i, rand(rng, 1:3)] += rand(rng) * 50; end   # CAH refer to regional
    # Some direct clinic → regional
    for i in 9:12; F[i, rand(rng, 1:3)] += rand(rng) * 5; end
    # Self-treated (diagonal)
    for i in 1:3;  F[i,i] = 500 + rand(rng) * 200; end
    for i in 4:8;  F[i,i] = 100 + rand(rng) * 50; end
    for i in 9:12; F[i,i] = 30  + rand(rng) * 20; end

    # Population and capacity per facility
    pop      = vcat([5000, 8000, 4000], [1500, 1200, 800, 1800, 600], [400, 500, 300, 350])
    capacity = vcat([200, 300, 150], [50, 40, 30, 60, 25], [10, 12, 8, 8])

    # Distance matrix (clinics to facilities, in km)
    n_zones = 8; n_fac = n
    dist     = abs.(randn(rng, n_zones, n_fac)) .* 50 .+ 10

    (names=names, types=types, F=F, pop=Float64.(pop),
     capacity=Float64.(capacity), dist=dist, n=n)
end

data = make_nd_facility_data()

# ── Section 1: Patient flow analysis ─────────────────────────────────────────

println("\n[1] Patient Flow Analysis ($(data.n) facilities)")
pf  = patient_flow_analysis(data.F; facility_names=data.names)
println("  $(lpad("Facility",22)) $(lpad("Self-suff%",10)) $(lpad("Net flow",9))")
println("  " * "-"^44)
for i in 1:data.n
    println("  $(lpad(data.names[i],22)) " *
            "$(lpad(round(100*pf.self_sufficiency[i],digits=1),10)) " *
            "$(lpad(round(pf.net_flow[i],digits=0),9))")
end

# ── Section 2: Referral centrality ────────────────────────────────────────────

println("\n[2] Referral Network Centrality")
rc  = referral_centrality(pf)
top3 = partialsortperm(rc.pagerank, 1:3; rev=true)
println("  Top 3 by PageRank:")
for i in top3
    println("    $(data.names[i]): PR=$(round(rc.pagerank[i],digits=4)), " *
            "Betweenness=$(round(rc.betweenness[i],digits=4))")
end

# ── Section 3: Catchment area ─────────────────────────────────────────────────

println("\n[3] Catchment Area (E2SFCA) — 8 population zones")
ca = catchment_area(data.pop[1:8], data.capacity, data.dist;
                    facility_names=data.names)
println("  Zone → assigned facility:")
for i in 1:min(8, length(ca.assignment))
    println("    Zone $i → $(data.names[ca.assignment[i]]) (utilisation=$(round(100*ca.utilisation_rate[ca.assignment[i]],digits=1))%)")
end

# ── Section 4: SIR epidemic model ─────────────────────────────────────────────

println("\n[4] SIR Epidemic Model — Influenza-like illness")
sir = sir_model(770000, 50;     # ND population ≈ 770K
                β=0.25, γ=0.1,
                tspan=(0.0, 180.0))
println("  R₀ = $(round(sir.R0, digits=2))")
println("  Peak prevalence: $(round(100*sir.peak_I, digits=2))%  at day $(round(sir.peak_time, digits=0))")
println("  Final attack rate: $(round(100*sir.final_size, digits=1))%")

# ── Section 5: SEIRD with interventions ──────────────────────────────────────

println("\n[5] SEIRD Model — COVID-19 scenario")
seird_base = seird_model(770000; β=0.4, σ=0.2, γ=0.07, μ=0.01)
seird_int  = seird_model(770000; β=0.2, σ=0.2, γ=0.07, μ=0.01)  # 50% NPI reduction
println("  Baseline R₀: $(round(seird_base.R0, digits=2)), " *
        "Peak I: $(round(100*seird_base.peak_I, digits=2))%")
println("  Intervention R₀: $(round(seird_int.R0, digits=2)), " *
        "Peak I: $(round(100*seird_int.peak_I, digits=2))%")
println("  Deaths (baseline):     $(round(100*seird_base.D[end], digits=2))%")
println("  Deaths (intervention): $(round(100*seird_int.D[end], digits=2))%")
println("  IFR: $(round(100*seird_base.ifr, digits=2))%")
println("  Herd immunity threshold: $(round(100*seird_int.herd_threshold, digits=1))%")

# ── Section 6: R₀ estimation from incidence ───────────────────────────────────

println("\n[6] R₀ Estimation from Observed Incidence")
rng     = MersenneTwister(3)
inc_obs = [round(Int, 5 * 1.25^t + 2*rand(rng)) for t in 0:12]
res_r0  = estimate_r0(Float64.(inc_obs); method=:exponential_growth, γ=0.1, n_points=8)
println("  Observed incidence first 13 days: $(inc_obs[1:5])...")
println("  Estimated R₀: $(round(res_r0.R0, digits=2)) " *
        "(growth rate r=$(round(res_r0.growth_rate, digits=3)))")

# ── Section 7: Network SIR ────────────────────────────────────────────────────

println("\n[7] Stochastic Network SIR")
g_net = pf.referral_graph
rng   = MersenneTwister(42)
net_s = network_sir(g_net, [1];  # seed from Bismarck (node 1)
                    β=0.2, γ=0.1, n_steps=60, n_sims=30, rng=rng)
println("  Peak I (mean): $(round(maximum(net_s.I_mean)*100, digits=2))%")
println("  At step 60, S=$(round(net_s.S_mean[end],digits=3)) " *
        "I=$(round(net_s.I_mean[end],digits=3)) " *
        "R=$(round(net_s.R_mean[end],digits=3))")

# ── Section 8: Network report ─────────────────────────────────────────────────

println("\n[8] Network Report")
rpt = network_report(g_net, sir; model_name="ND-Facility-Network")
print_network_report(rpt)

println("\n✓ Network & epidemic analysis complete.")
