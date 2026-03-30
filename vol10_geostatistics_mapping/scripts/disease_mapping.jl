#!/usr/bin/env julia
# scripts/disease_mapping.jl
# Bayesian disease mapping of ND county health outcomes

using Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "packages", "DiseaseMapping", "src", "DiseaseMapping.jl"))
using .DiseaseMapping

println("=" ^ 65)
println("  Vol 10 — Disease Mapping: ND County Health Outcomes")
println("  SMR · EB Smoothing · BYM Model · Spatial Scan")
println("=" ^ 65)

# ── Simulated ND county data ──────────────────────────────────────────────────

function make_nd_disease_data(n=40; seed=42)
    rng    = MersenneTwister(seed)
    # Population sizes (counties range 1 000–80 000)
    pop    = round.(Int, 1000 .+ 79000 .* rand(rng, n).^2)
    # Age-sex standardised expected counts (rate ≈ 0.008 per person)
    E      = pop .* (0.006 .+ 0.004 .* rand(rng, n))

    # ND bounding box
    lons   = -104.1 .+ 7.6 .* rand(rng, n)
    lats   =   45.9 .+ 3.1 .* rand(rng, n)
    coords = hcat(lons, lats)

    # True relative risk: western cluster + eastern high-risk strip
    η_true = zeros(n)
    for i in 1:n
        η_true[i] = 0.05 * (lons[i] + 104.1) / 7.6   # mild east-west gradient
    end
    # Inject a local cluster in the northwest
    for i in 1:n
        if lons[i] < -101.0 && lats[i] > 47.5
            η_true[i] += 0.5
        end
    end
    rr_true = exp.(η_true)

    # Observed counts ~ Poisson(E * RR)
    O = [rand(rng, Distributions_fallback(E[i] * rr_true[i])) for i in 1:n]

    areas = ["ND-$(lpad(i,2,'0'))" for i in 1:n]
    (O=Float64.(O), E=E, coords=coords, lons=lons, lats=lats,
     rr_true=rr_true, areas=areas, n=n)
end

# Simple Poisson random deviate (no Distributions dependency)
function rpois(rng, λ)
    if λ < 30
        L = exp(-λ); k = 0; p = 1.0
        while p > L; k += 1; p *= rand(rng); end
        return k - 1
    else
        return max(0, round(Int, λ + sqrt(λ) * randn(rng)))
    end
end

function make_nd_disease_data2(n=40; seed=42)
    rng    = MersenneTwister(seed)
    pop    = round.(Int, 1000 .+ 79000 .* rand(rng, n).^2)
    E      = pop .* (0.006 .+ 0.004 .* rand(rng, n))
    lons   = -104.1 .+ 7.6 .* rand(rng, n)
    lats   =   45.9 .+ 3.1 .* rand(rng, n)
    coords = hcat(lons, lats)
    η_true = 0.05 .* (lons .+ 104.1) ./ 7.6
    for i in 1:n
        if lons[i] < -101.0 && lats[i] > 47.5
            η_true[i] += 0.5
        end
    end
    rr_true = exp.(η_true)
    O = Float64.([rpois(rng, E[i] * rr_true[i]) for i in 1:n])
    areas = ["ND-$(lpad(i,2,'0'))" for i in 1:n]
    (O=O, E=E, coords=coords, lons=lons, lats=lats,
     rr_true=rr_true, areas=areas, n=n)
end

data = make_nd_disease_data2()
println("\n► $(data.n) ND counties  |  Total O=$(Int(sum(data.O)))  E=$(round(sum(data.E),digits=1))")
println("  Overall SMR: $(round(sum(data.O)/sum(data.E), digits=3))")

# ── Section 1: Standardised Mortality Ratios ──────────────────────────────────

println("\n[1] Standardised Mortality Ratios (SMR)")
smr_results = batch_smr(data.O, data.E; areas=data.areas)
sig_areas   = [r for r in smr_results if r.significant]
smrs        = [r.smr for r in smr_results]
println("  Median SMR: $(round(median(smrs), digits=3))")
println("  Range: [$(round(minimum(smrs),digits=3)), $(round(maximum(smrs),digits=3))]")
println("  Significant areas (p<0.05): $(length(sig_areas))/$(data.n)")

# Top 3 highest SMR
top3 = sort(smr_results, by=r->r.smr, rev=true)[1:3]
for r in top3
    println("    $(r.area): SMR=$(round(r.smr,digits=3))  95%CI=[$(round(r.lower_ci,digits=3)), $(round(r.upper_ci,digits=3))]  p=$(round(r.p_value,digits=4))")
end

# ── Section 2: Indirect Standardisation ──────────────────────────────────────

println("\n[2] Indirect Age Standardisation (5 age groups)")
rng2  = MersenneTwister(99)
n_age = 5
# Reference rates per age band (increasing with age)
ref_rates = [0.001, 0.003, 0.008, 0.020, 0.050]
# Population by age band for each county
pop_age   = [abs.(round.(Int, data.E[i]/0.008 .* (0.15 .+ 0.1*randn(rng2, n_age)))) for i in 1:data.n]
pop_age   = [max.(pa, 10) for pa in pop_age]
counts_age = [round.(Int, pop_age[i] .* ref_rates .* (0.8 .+ 0.4*rand(rng2, n_age))) for i in 1:data.n]

E_std, O_std = indirect_standardise(counts_age, pop_age, ref_rates)
println("  Computed expected counts for $(data.n) areas")
println("  Mean E (indirect): $(round(mean(E_std), digits=2))")
println("  Mean O (indirect): $(round(mean(O_std), digits=2))")
println("  Aggregate SMR: $(round(sum(O_std)/sum(E_std), digits=3))")

# ── Section 3: Empirical Bayes Smoothing ──────────────────────────────────────

println("\n[3] Empirical Bayes Smoothing (Gamma-Poisson)")
eb = eb_smooth(data.O, data.E)
println("  α̂ (shape): $(round(eb.α_hat, digits=4))")
println("  β̂ (rate):  $(round(eb.β_hat, digits=4))")
println("  Raw SMR range:  [$(round(minimum(eb.smr_raw),digits=3)), $(round(maximum(eb.smr_raw),digits=3))]")
println("  EB θ̂  range:   [$(round(minimum(eb.θ_hat), digits=3)), $(round(maximum(eb.θ_hat), digits=3))]")
println("  Mean shrinkage: $(round(mean(eb.shrinkage)*100, digits=1))%")

# Kernel smoothed rates
kr_smooth = kernel_smooth_rates(data.O, data.E, data.coords; bandwidth=2.0)
println("  Kernel-smoothed RR range: [$(round(minimum(kr_smooth),digits=3)), $(round(maximum(kr_smooth),digits=3))]")

# ── Section 4: Spatial adjacency & ICAR structure ────────────────────────────

println("\n[4] Spatial Structure (adjacency graph)")
W, Q, m_i = build_adjacency(data.coords; threshold=2.5)
n_edges    = sum(W) ÷ 2
println("  Adjacency threshold: 2.5 degrees")
println("  Edges: $n_edges")
println("  Mean neighbours: $(round(mean(m_i), digits=2))")
println("  Isolated nodes: $(sum(m_i .== 0))")

# ── Section 5: BYM Model ──────────────────────────────────────────────────────

println("\n[5] BYM Spatial Random Effects Model")
println("  Running MCMC (2 000 iter, 500 warm-up)...")
rng3 = MersenneTwister(2024)
bym  = bym_fit(data.O, data.E, W, Q;
               n_iter=2000, n_warmup=500, rng=rng3)

println("  τ_u posterior mean: $(round(bym.τ_u_mean, digits=3))")
println("  τ_v posterior mean: $(round(bym.τ_v_mean, digits=3))")
println("  DIC: $(round(bym.dic, digits=2))   pD: $(round(bym.pd, digits=2))")
println("  RR posterior mean range: [$(round(minimum(bym.rr),digits=3)), $(round(maximum(bym.rr),digits=3))]")

# Exceedance probability: P(RR > 1.2 | data) from posterior intervals
exceed = sum(bym.rr_lower .> 1.2)
println("  Areas with 95% CI above 1.2: $exceed")

# Compare BYM vs raw SMR correlation with truth
corr_bym = cor(bym.rr, data.rr_true)
corr_raw = cor(smrs,    data.rr_true)
println("  Corr(BYM RR, true RR): $(round(corr_bym, digits=3))")
println("  Corr(raw SMR, true RR): $(round(corr_raw, digits=3))")

# ── Section 6: Spatial Scan Statistic ────────────────────────────────────────

println("\n[6] Spatial Scan Statistic (Kulldorff, 1997)")
rng4  = MersenneTwister(999)
scans = spatial_scan(data.O, data.E, data.coords;
                     max_pop_frac=0.4, n_sim=199, alpha=0.05, rng=rng4)
sig_scans = [s for s in scans if s.significant]
println("  Candidate windows evaluated: $(length(scans))")
println("  Significant clusters: $(length(sig_scans))")
if !isempty(sig_scans)
    top = sig_scans[1]
    println("  Top cluster:")
    println("    Centre: area $(top.centre_idx)  Radius: $(round(top.radius, digits=3))°")
    println("    O_in=$(round(top.O_inside,digits=1))  E_in=$(round(top.E_inside,digits=3))")
    println("    LLR=$(round(top.llr,digits=3))  p=$(round(top.p_value,digits=4))")
    println("    SMR_in=$(round(top.O_inside/max(top.E_inside,1e-6), digits=3))")
end

println("\n✓ Disease mapping pipeline complete.")
