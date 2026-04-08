#!/usr/bin/env julia
# scripts/facility_siting.jl
# Optimal siting of ND rural health clinics

using Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "packages", "FacilityLocation", "src", "FacilityLocation.jl"))
using .FacilityLocation

println("=" ^ 65)
println("  Vol 12 — Facility Siting: ND Rural Clinic Optimisation")
println("  p-Median · MCLP · Set Cover · Capacitated FLP")
println("=" ^ 65)

function make_nd_demand(n=53; seed=42)
    rng  = MersenneTwister(seed)
    lons = -104.1 .+ 7.6 .* rand(rng, n)
    lats =   45.9 .+ 3.1 .* rand(rng, n)
    pop  = round.(Int, 1000 .+ 49000 .* rand(rng, n).^1.5)
    pts  = hcat(lons .- mean(lons), lats .- mean(lats))
    (pts=pts, pop=Float64.(pop), lons=lons, lats=lats, n=n)
end

function make_nd_candidates(n=30; seed=99)
    rng  = MersenneTwister(seed)
    lons = -104.0 .+ 7.5 .* rand(rng, n)
    lats =   46.0 .+ 3.0 .* rand(rng, n)
    hcat(lons .- (-100.3), lats .- 47.45)
end

data  = make_nd_demand()
cands = make_nd_candidates()

println("\n► $(data.n) ND counties  |  $(size(cands,1)) candidate sites")
println("  Total population: $(sum(data.pop))")
println("  Mean county pop:  $(round(mean(data.pop)))")

# ── Section 1: p-Median ───────────────────────────────────────────────────────

println("\n[1] p-Median Facility Location")
for p in [3, 5, 8]
    rng = MersenneTwister(p)
    res = p_median(data.pts, cands, p; weights=data.pop, rng=rng)
    println("  p=$p: obj=$(round(res.objective,digits=2))  " *
            "sites=$(res.open_facilities[1:min(p,5)]...)  iters=$(res.iterations)")
end

# Detailed p=5 analysis
rng5 = MersenneTwister(5)
pm5  = p_median(data.pts, cands, 5; weights=data.pop, rng=rng5)
println("  p=5 improvement path: $(round.(pm5.improvement_history[1:min(5,end)],digits=2))...")
println("  Mean weighted distance to nearest clinic: $(round(pm5.objective/sum(data.pop),digits=4))")

# ── Section 2: Voronoi Catchments ─────────────────────────────────────────────

println("\n[2] Voronoi Catchment Areas (p=5)")
fac_pts = cands[pm5.open_facilities, :]
vc      = catchment_voronoi(data.pts, fac_pts; weights=data.pop)
println("  Catchment populations: $(round.(sort(vc.catchment_pop,rev=true),digits=0))")
println("  Mean distance to clinic: $(round(mean(vc.mean_dist),digits=3))")
println("  Max catchment pop: $(round(maximum(vc.catchment_pop)))")

# ── Section 3: MCLP ──────────────────────────────────────────────────────────

println("\n[3] Maximal Coverage Location (radius=0.5°, ≈55km)")
for p in [3, 5, 8]
    rng = MersenneTwister(100+p)
    res = mclp(data.pts, cands, p; coverage_radius=0.5, weights=data.pop, rng=rng)
    println("  p=$p: $(round(res.coverage_fraction*100,digits=1))% pop covered  sites=$(res.open_facilities[1:min(p,5)]...)")
end

# ── Section 4: Set Covering ──────────────────────────────────────────────────

println("\n[4] Set Cover (minimum facilities for full coverage)")
for r in [0.4, 0.6, 1.0]
    res = set_cover(data.pts, cands; coverage_radius=r, weights=data.pop)
    println("  radius=$(r)°: $(res.n_facilities) facilities cover $(round(res.coverage_fraction*100,digits=1))% pop")
end

# ── Section 5: Capacitated FLP ───────────────────────────────────────────────

println("\n[5] Capacitated Facility Location (p=5)")
# Each facility serves up to 250,000 person-equivalent units
cap_per_fac = fill(sum(data.pop)/4, size(cands,1))
rng_cap     = MersenneTwister(7)
cap_res     = cap_flp(data.pts, cands, 5;
                       weights=data.pop, capacities=cap_per_fac, rng=rng_cap)
println("  Objective: $(round(cap_res.objective,digits=2))")
println("  Feasible: $(cap_res.feasible)")
println("  Open facilities: $(cap_res.open_facilities)")
println("  Capacity used: $(round.(cap_res.capacity_used,digits=0))")
println("  Capacity slack: $(round.(cap_res.capacity_slack,digits=0))")

# ── Section 6: Comparison ────────────────────────────────────────────────────

println("\n[6] Method Comparison (p=5, equal weights)")
rng6 = MersenneTwister(6)
pm_eq  = p_median(data.pts, cands, 5; rng=rng6)
mc_eq  = mclp(data.pts, cands, 5; coverage_radius=0.5, rng=rng6)
sc_eq  = set_cover(data.pts, cands; coverage_radius=0.5)
println("  p-Median (minimize dist):  obj=$(round(pm_eq.objective,digits=2))")
println("  MCLP (maximize coverage):  $(round(mc_eq.coverage_fraction*100,digits=1))% covered")
println("  Set cover (min # facilities): $(sc_eq.n_facilities) facilities for 50% coverage")

# ── Section 7: Full report ────────────────────────────────────────────────────

println("\n[7] Full Facility Report")
rng7 = MersenneTwister(77)
rpt  = facility_report(data.pts, cands;
                        study_name="ND Rural Clinics",
                        p=5, coverage_radius=0.5,
                        weights=data.pop, rng=rng7)
print_facility_report(rpt)

println("\n✓ Facility siting pipeline complete.")
