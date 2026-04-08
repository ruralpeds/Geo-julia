#!/usr/bin/env julia
# scripts/routing.jl
# ND EMS routing and ambulance coverage optimisation

using Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "packages", "HealthRouting", "src", "HealthRouting.jl"))
using .HealthRouting

println("=" ^ 65)
println("  Vol 12 — Health Routing: ND EMS Optimisation")
println("  TSP · VRP · MEXCLP · Erlang-C Staffing")
println("=" ^ 65)

function make_nd_clients(n=20; seed=42)
    rng = MersenneTwister(seed)
    hcat(rand(rng, n) .* 7.6, rand(rng, n) .* 3.1)
end

function make_nd_incidents(n=15; seed=43)
    rng = MersenneTwister(seed)
    hcat(rand(rng, n) .* 7.6, rand(rng, n) .* 3.1)
end

clients  = make_nd_clients()
depot    = [3.8, 1.55]  # central depot (Bismarck area)
demands  = rand(MersenneTwister(1), size(clients,1)) .* 3 .+ 1
println("\n► $(size(clients,1)) service locations  |  depot at $(depot)")
println("  Total demand: $(round(sum(demands),digits=1))")

# ── Section 1: TSP ────────────────────────────────────────────────────────────

println("\n[1] Travelling Salesman Problem (inspection route)")
rng1 = MersenneTwister(1)
nn   = tsp_nn(clients; rng=rng1)
to   = tsp_two_opt(clients; init_tour=nn.tour, rng=rng1)
println("  NN heuristic distance:  $(round(nn.distance,digits=3))")
println("  2-opt distance:         $(round(to.distance,digits=3))")
println("  Improvement:            $(round(to.improvement,digits=3)) ($(round(100*to.improvement/nn.distance,digits=1))%)")
println("  Tour (first 8 stops):   $(to.tour[1:min(8,end)])")

# ── Section 2: VRP ────────────────────────────────────────────────────────────

println("\n[2] Vehicle Routing Problem (home health visits)")
for cap in [5.0, 8.0, 15.0]
    rng2 = MersenneTwister(2)
    res  = vrp_cw(clients, depot; demands=demands, capacity=cap)
    println("  Capacity=$(cap): $(res.n_vehicles) vehicles  total dist=$(round(res.total_distance,digits=2))")
end

# Detailed VRP with capacity=8
rng2d = MersenneTwister(2)
vrp8  = vrp_cw(clients, depot; demands=demands, capacity=8.0)
println("  Routes (capacity=8):")
for (k, (route, d, load)) in enumerate(zip(vrp8.routes, vrp8.route_distances, vrp8.capacity_used))
    println("    Route $k: stops=$(route)  dist=$(round(d,digits=2))  load=$(round(load,digits=1))")
end

# ── Section 3: MEXCLP ────────────────────────────────────────────────────────

println("\n[3] MEXCLP: Maximum Expected Coverage")
demand_pts = make_nd_incidents(25)
station_candidates = make_nd_clients(15; seed=50)

for (p, q) in [(3,0.3),(5,0.3),(5,0.5)]
    rng3 = MersenneTwister(3)
    res  = mexclp(demand_pts, station_candidates, p;
                  coverage_radius=1.0, busy_fraction=q, rng=rng3)
    println("  p=$p, q=$q: expected coverage=$(round(res.total_expected_coverage*100,digits=1))%  " *
            "stations=$(res.facility_locs)")
end

# ── Section 4: Dispatch Assignment ───────────────────────────────────────────

println("\n[4] Incident Dispatch Assignment")
stations  = station_candidates[1:5,:]
incidents = make_nd_incidents(8; seed=44)
available = [2, 1, 3, 1, 2]
asgn      = dispatch_assignment(incidents, stations, available)
println("  Incident → station assignments: $asgn")
for s in 1:5
    n_assigned = sum(asgn .== s)
    println("  Station $s: $(n_assigned) incidents  ($(available[s]) units available)")
end

# ── Section 5: Erlang-C Staffing ─────────────────────────────────────────────

println("\n[5] Erlang-C EMS Staffing Analysis")
println("  Arrival rate λ (calls/hr), service rate μ (1/hr), c servers")
println()
for (λ, μ, c) in [(2.0,1.0,3),(3.0,1.0,4),(5.0,1.0,6),(5.0,2.0,4)]
    ec = erlang_c(λ, μ, c)
    println("  λ=$(λ) μ=$(μ) c=$c: P(wait)=$(round(ec.p_wait,digits=3))  " *
            "E[wait]=$(round(ec.mean_wait,digits=3))  min_servers=$(ec.min_servers)")
end

# ── Section 6: Staffing optimisation ─────────────────────────────────────────

println("\n[6] Minimum Staffing for Service Level (P(wait) ≤ 0.2)")
for λ in [1.0, 2.0, 4.0, 8.0]
    ec = erlang_c(λ, 1.0, max(2, ceil(Int, λ)); target_pw=0.2)
    println("  λ=$(λ): minimum $(ec.min_servers) servers → P(wait)=$(round(ec.p_wait,digits=3))")
end

# ── Section 7: Full report ────────────────────────────────────────────────────

println("\n[7] Routing Report")
rng7 = MersenneTwister(77)
rpt  = routing_report(clients, depot; λ=2.0, μ=1.0, c_init=3, rng=rng7)
print_routing_report(rpt)

println("\n✓ Health routing pipeline complete.")
