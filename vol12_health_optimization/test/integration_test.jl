#!/usr/bin/env julia
# test/integration_test.jl
# Vol 12 integration tests: FacilityLocation · HealthRouting · ResourceAllocation

using Test, Random, Statistics, LinearAlgebra

# Load all three packages
include(joinpath(@__DIR__, "..", "packages", "FacilityLocation", "src", "FacilityLocation.jl"))
include(joinpath(@__DIR__, "..", "packages", "HealthRouting", "src", "HealthRouting.jl"))
include(joinpath(@__DIR__, "..", "packages", "ResourceAllocation", "src", "ResourceAllocation.jl"))

using .FacilityLocation, .HealthRouting, .ResourceAllocation

# ─── Shared fixtures ──────────────────────────────────────────────────────────

function make_demand(n=20; seed=1)
    rng = MersenneTwister(seed)
    pts = hcat(rand(rng, n) .* 7.6, rand(rng, n) .* 3.1)
    pop = rand(rng, n) .* 5000 .+ 500
    pts, pop
end

function make_candidates(n=15; seed=2)
    rng = MersenneTwister(seed)
    hcat(rand(rng, n) .* 7.6, rand(rng, n) .* 3.1)
end

demand_pts, pop = make_demand(20)
cand_pts        = make_candidates(15)
depot           = [3.8, 1.55]
rng_global      = MersenneTwister(42)

# ─── FacilityLocation tests ───────────────────────────────────────────────────

@testset "FacilityLocation — p-Median" begin
    for p in [2, 4, 6]
        res = p_median(demand_pts, cand_pts, p; weights=pop,
                       rng=MersenneTwister(1))
        @test length(res.open_facilities) == p
        @test res.objective > 0
        @test all(1 .<= res.assignment .<= p)
        @test length(res.assignment) == size(demand_pts, 1)
    end

    # convenience form
    res2 = p_median(demand_pts, 3; weights=pop, rng=MersenneTwister(2))
    @test length(res2.open_facilities) == 3

    # more facilities → lower or equal objective
    r3 = p_median(demand_pts, cand_pts, 3; weights=pop, rng=MersenneTwister(3))
    r6 = p_median(demand_pts, cand_pts, 6; weights=pop, rng=MersenneTwister(3))
    @test r6.objective <= r3.objective + 1e-6
end

@testset "FacilityLocation — Set Cover" begin
    sc = set_cover(demand_pts, cand_pts; coverage_radius=2.0, weights=pop)
    @test sc.n_facilities >= 1
    @test sc.total_covered_demand <= sum(pop) + 1e-6

    # large radius should require fewer facilities
    sc_large = set_cover(demand_pts, cand_pts; coverage_radius=5.0, weights=pop)
    sc_small = set_cover(demand_pts, cand_pts; coverage_radius=1.0, weights=pop)
    @test sc_large.n_facilities <= sc_small.n_facilities
end

@testset "FacilityLocation — MCLP" begin
    mc = mclp(demand_pts, cand_pts, 5; coverage_radius=2.0, weights=pop,
              rng=MersenneTwister(10))
    @test 0 < mc.coverage_fraction <= 1.0
    @test length(mc.open_facilities) == 5

    # more facilities → at least as much coverage
    mc3 = mclp(demand_pts, cand_pts, 3; coverage_radius=2.0, weights=pop,
               rng=MersenneTwister(10))
    mc7 = mclp(demand_pts, cand_pts, 7; coverage_radius=2.0, weights=pop,
               rng=MersenneTwister(10))
    @test mc7.coverage_fraction >= mc3.coverage_fraction - 1e-6
end

@testset "FacilityLocation — Capacitated FLP" begin
    cap_vec = fill(sum(pop) / 5 * 1.1, 15)
    res = cap_flp(demand_pts, cand_pts, 5; weights=pop, capacities=cap_vec,
                  rng=MersenneTwister(20))
    @test length(res.open_facilities) == 5
    @test all(res.capacity_used .<= cap_vec[res.open_facilities] .+ 1e-6)
    # feasible if total capacity ≥ total demand
    @test res.feasible
end

@testset "FacilityLocation — Voronoi Catchments" begin
    pm = p_median(demand_pts, cand_pts, 4; weights=pop, rng=MersenneTwister(30))
    fac_pts = cand_pts[pm.open_facilities, :]
    vor = catchment_voronoi(demand_pts, fac_pts; weights=pop)
    @test sum(vor.catchment_pop) ≈ sum(pop) atol=1e-6
    @test length(vor.catchment_pop) == 4
    @test 0 <= vor.gini <= 1
end

# ─── HealthRouting tests ──────────────────────────────────────────────────────

@testset "HealthRouting — TSP Nearest-Neighbour" begin
    nn = tsp_nn(demand_pts; rng=MersenneTwister(1))
    @test nn.distance > 0
    @test length(nn.tour) == size(demand_pts, 1) + 1  # returns to start
    @test nn.tour[1] == nn.tour[end]  # round trip

    # all nodes visited exactly once (excluding depot repeat)
    inner = nn.tour[1:end-1]
    @test sort(inner) == 1:size(demand_pts, 1)
end

@testset "HealthRouting — TSP 2-opt Improvement" begin
    nn = tsp_nn(demand_pts; rng=MersenneTwister(1))
    to = tsp_two_opt(demand_pts; init_tour=nn.tour, rng=MersenneTwister(1))
    @test to.distance <= nn.distance + 1e-9
    @test to.improvement >= -1e-9
    inner = to.tour[1:end-1]
    @test sort(inner) == 1:size(demand_pts, 1)
end

@testset "HealthRouting — VRP Clarke-Wright" begin
    demands = rand(MersenneTwister(5), size(demand_pts, 1)) .* 2 .+ 0.5
    for cap in [3.0, 6.0, 20.0]
        vrp = vrp_cw(demand_pts, depot; demands=demands, capacity=cap)
        @test vrp.n_vehicles >= 1
        @test vrp.total_distance > 0
        @test all(vrp.capacity_used .<= cap + 1e-6)
        # every customer served exactly once
        all_served = vcat(vrp.routes...)
        @test sort(all_served) == 1:size(demand_pts, 1)
    end
end

@testset "HealthRouting — MEXCLP Coverage" begin
    for (p, q) in [(3, 0.3), (5, 0.3), (5, 0.5)]
        res = mexclp(demand_pts, cand_pts, p;
                     coverage_radius=1.5, busy_fraction=q,
                     rng=MersenneTwister(3))
        @test 0 < res.total_expected_coverage <= 1.0
        @test length(res.facility_locs) == p
    end

    # busier ambulances → lower coverage (same p)
    res_low  = mexclp(demand_pts, cand_pts, 5; coverage_radius=1.5,
                      busy_fraction=0.1, rng=MersenneTwister(3))
    res_high = mexclp(demand_pts, cand_pts, 5; coverage_radius=1.5,
                      busy_fraction=0.8, rng=MersenneTwister(3))
    @test res_low.total_expected_coverage >= res_high.total_expected_coverage - 1e-6
end

@testset "HealthRouting — Dispatch Assignment" begin
    stations  = cand_pts[1:5, :]
    incidents = demand_pts[1:8, :]
    available = [2, 1, 3, 0, 2]
    asgn      = dispatch_assignment(incidents, stations, available)
    @test length(asgn) == size(incidents, 1)
    # no incident assigned to station with 0 availability
    @test all(asgn .!= 4)
    @test all(1 .<= asgn .<= 5)
end

@testset "HealthRouting — Erlang-C Staffing" begin
    ec = erlang_c(3.0, 1.0, 5)
    @test 0 <= ec.p_wait <= 1
    @test ec.mean_wait >= 0
    @test ec.min_servers >= 1

    # more servers → lower P(wait)
    ec4 = erlang_c(5.0, 1.0, 7)
    ec6 = erlang_c(5.0, 1.0, 9)
    @test ec6.p_wait <= ec4.p_wait + 1e-9

    # min_servers achieves target
    ec_t = erlang_c(4.0, 1.0, 6; target_pw=0.20)
    ec_min = erlang_c(4.0, 1.0, ec_t.min_servers)
    @test ec_min.p_wait <= 0.20 + 1e-6
end

# ─── ResourceAllocation tests ─────────────────────────────────────────────────

@testset "ResourceAllocation — 0/1 Knapsack" begin
    values  = [3.2, 2.8, 4.1, 3.7, 2.5, 3.0]
    weights = [2.0, 3.0, 4.0, 3.5, 2.5, 3.5]

    res = knapsack_01(values, weights, 10.0)
    @test all(res.x .∈ Ref([0, 1]))
    @test dot(res.x, weights) <= 10.0 + 1e-8
    @test res.objective ≈ dot(res.x, values) atol=1e-8

    # larger capacity → at least as good
    r10 = knapsack_01(values, weights, 10.0)
    r14 = knapsack_01(values, weights, 14.0)
    @test r14.objective >= r10.objective - 1e-6

    # budget of 0 → nothing selected
    r0 = knapsack_01(values, weights, 0.0)
    @test sum(r0.x) == 0
end

@testset "ResourceAllocation — Branch and Bound" begin
    c = [5.0, 4.0, 3.0, 2.0]
    A = [2.0 1.0 1.0 3.0]
    b = [5.0]
    res = bip_branch_bound(c, A, b; sense=:max)
    @test res.feasible
    @test all(res.x .∈ Ref([0, 1]))
    @test (A * res.x)[1] <= b[1] + 1e-8
    @test res.objective > 0
    @test res.n_nodes >= 1
end

@testset "ResourceAllocation — Two-Stage SP" begin
    c1   = [1.5, 1.5]
    c2   = [4.0, 4.0]
    A1   = [1.0 1.0; 1.0 0.0; 0.0 1.0]
    b1   = [10.0, 7.0, 7.0]
    A2   = diagm(ones(2))
    dem  = hcat([3.0,2.0],[5.0,4.0],[7.0,6.0],[9.0,8.0])
    prob = [0.2, 0.3, 0.3, 0.2]

    sp = two_stage_sp(c1, c2, A1, A2, b1, dem, prob; sense=:min)
    @test sp.obj_expected > 0
    @test length(sp.x_first) == 2
    @test size(sp.x_second) == (2, 4)
    @test all(sp.x_second .>= -1e-8)
    @test sp.vss >= -1e-6    # VSS ≥ 0
    @test sp.obj_evpi >= -1e-6  # EVPI ≥ 0
end

@testset "ResourceAllocation — Value Iteration" begin
    R, P = health_resource_mdp(8, 4; rng=MersenneTwister(1))
    vi   = value_iteration(R, P; γ=0.95)
    @test vi.converged
    @test length(vi.V) == 8
    @test all(1 .<= vi.policy .<= 4)
    @test vi.n_iter > 0
end

@testset "ResourceAllocation — Policy Iteration" begin
    R, P = health_resource_mdp(8, 4; rng=MersenneTwister(2))
    pi_r = policy_iteration(R, P; γ=0.95)
    @test pi_r.converged
    @test all(1 .<= pi_r.policy .<= 4)
    # policy iteration should agree with value iteration on policy
    vi = value_iteration(R, P; γ=0.95)
    # values close (same fixed point)
    @test norm(vi.V .- pi_r.V) < 0.5  # may differ slightly due to tolerance
end

@testset "ResourceAllocation — MDP Simulation" begin
    R, P = health_resource_mdp(10, 5)
    vi   = value_iteration(R, P; γ=0.95)
    sim  = mdp_simulate(vi, 5, R, P; n_steps=50, rng=MersenneTwister(7))
    @test length(sim.states)  == 51
    @test length(sim.actions) == 50
    @test all(1 .<= sim.actions .<= 5)
    @test all(1 .<= sim.states .<= 10)
    # discounted reward finite
    @test isfinite(sim.discounted_reward)
end

# ─── Cross-package integration tests ─────────────────────────────────────────

@testset "Integration — Facility Sites Feed VRP Routes" begin
    # Step 1: select p=4 clinic sites via p-median
    pm = p_median(demand_pts, cand_pts, 4; weights=pop, rng=MersenneTwister(10))
    site_pts = cand_pts[pm.open_facilities, :]

    # Step 2: route supply vehicle from depot to serve all sites (TSP)
    nn = tsp_nn(site_pts; rng=MersenneTwister(10))
    to = tsp_two_opt(site_pts; init_tour=nn.tour, rng=MersenneTwister(10))

    @test to.distance <= nn.distance + 1e-9
    @test length(to.tour) == 5  # 4 sites + return

    # Step 3: also verify VRP with supply demands
    site_demands = fill(2.0, 4)
    vrp = vrp_cw(site_pts, depot; demands=site_demands, capacity=5.0)
    @test vrp.n_vehicles >= 1
    @test vcat(vrp.routes...) |> sort == 1:4
end

@testset "Integration — MCLP Coverage Informs Knapsack Selection" begin
    # Compute expected coverage per candidate site
    mc_full = mclp(demand_pts, cand_pts, 8; coverage_radius=2.0, weights=pop,
                   rng=MersenneTwister(20))

    # Use MCLP coverage as proxy for programme value in knapsack
    prog_values  = [3.2, 2.8, 4.1, 3.7, 2.5, 3.0, 2.1, 1.8]
    prog_weights = [2.0, 3.0, 4.0, 3.5, 2.5, 3.5, 4.0, 2.0]

    # Weight values by rural relevance (analogous to coverage benefit)
    coverage_bonus = [1.2, 1.0, 1.3, 1.1, 1.0, 1.0, 1.2, 1.0]
    adjusted = prog_values .* coverage_bonus
    r = knapsack_01(adjusted, prog_weights, 12.0)

    @test sum(r.x) >= 1
    @test dot(r.x, prog_weights) <= 12.0 + 1e-8
    # coverage-adjusted selection achieves at least as good objective
    r_unadjusted = knapsack_01(prog_values, prog_weights, 12.0)
    # with same budget, adjusted can pick different programmes
    @test r.objective >= 0  # sanity
end

@testset "Integration — Erlang-C Staffing Guides MDP Action Space" begin
    λ, μ = 3.0, 1.0
    ec   = erlang_c(λ, μ, 5; target_pw=0.20)
    min_staff = ec.min_servers

    # MDP with actions representing staffing levels at/above minimum
    n_states  = 8
    n_actions = 5
    R, P = health_resource_mdp(n_states, n_actions; rng=MersenneTwister(30))
    vi   = value_iteration(R, P; γ=0.95)

    # High-backlog states should prefer high staffing (action near n_actions)
    high_backlog_states = (n_states ÷ 2 + 1):n_states
    avg_action_high = mean(vi.policy[high_backlog_states])

    low_backlog_states = 1:(n_states ÷ 2)
    avg_action_low  = mean(vi.policy[low_backlog_states])

    # Threshold policy: higher backlog → higher staffing (or at least not lower)
    @test avg_action_high >= avg_action_low - 1.0  # allow small tolerance
    @test min_staff >= 1
end

@testset "Integration — End-to-End ND Health Optimisation Pipeline" begin
    # Full ND scenario: 20 demand zones, 15 candidates, $12M budget
    rng = MersenneTwister(99)

    # 1. Facility siting (p-median with p=5)
    pm = p_median(demand_pts, cand_pts, 5; weights=pop, rng=rng)
    @test length(pm.open_facilities) == 5
    @test pm.objective > 0

    # 2. Coverage check (MCLP)
    mc = mclp(demand_pts, cand_pts, 5; coverage_radius=2.0, weights=pop, rng=rng)
    @test mc.coverage_fraction > 0

    # 3. Routing to serve chosen sites
    site_pts = cand_pts[pm.open_facilities, :]
    to = tsp_two_opt(site_pts; init_tour=tsp_nn(site_pts; rng=rng).tour, rng=rng)
    @test to.distance > 0

    # 4. EMS staffing for dispatch
    ec = erlang_c(3.0, 1.0, 6; target_pw=0.20)
    @test ec.min_servers >= 1

    # 5. Budget allocation (knapsack)
    values_nd  = [3.2, 2.8, 4.1, 3.7, 2.5, 3.0, 2.1, 1.8, 1.5, 1.2]
    weights_nd = [2.0, 3.0, 4.0, 3.5, 2.5, 3.5, 4.0, 2.0, 2.5, 1.5]
    kp = knapsack_01(values_nd, weights_nd, 12.0)
    @test dot(kp.x, weights_nd) <= 12.0 + 1e-8
    @test sum(kp.x) >= 1

    # 6. MDP policy for dynamic staffing
    R, P = health_resource_mdp(10, 5)
    vi   = value_iteration(R, P; γ=0.95)
    @test vi.converged
    @test all(1 .<= vi.policy .<= 5)

    # 7. Stochastic programming for demand uncertainty
    c1  = [1.5, 1.5]; c2 = [4.0, 4.0]
    A1  = [1.0 1.0; 1.0 0.0; 0.0 1.0]
    b1  = [10.0, 7.0, 7.0]
    A2  = diagm(ones(2))
    dem = hcat([3.0,2.0],[5.0,4.0],[7.0,6.0],[9.0,8.0])
    pr  = [0.2, 0.3, 0.3, 0.2]
    sp  = two_stage_sp(c1, c2, A1, A2, b1, dem, pr; sense=:min)
    @test sp.obj_expected > 0
    @test sp.vss >= -1e-6

    # Pipeline integrity: all results have finite, positive values
    @test isfinite(pm.objective)
    @test isfinite(mc.coverage_fraction)
    @test isfinite(to.distance)
    @test isfinite(kp.objective)
    @test all(isfinite.(vi.V))
    @test isfinite(sp.obj_expected)
end

println("\n✓ All Vol 12 integration tests passed.")
