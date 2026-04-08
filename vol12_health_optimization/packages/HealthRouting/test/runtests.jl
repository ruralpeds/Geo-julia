using Test, Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "src", "HealthRouting.jl"))
using .HealthRouting

function make_pts(n=10; seed=1)
    rng = MersenneTwister(seed)
    hcat(rand(rng, n) .* 20, rand(rng, n) .* 20)
end

@testset "TSP nearest-neighbour" begin
    pts = make_pts(8)
    res = tsp_nn(pts)
    @test length(res.tour) == 8
    @test allunique(res.tour)
    @test res.distance > 0.0
    @test res.method == :nearest_neighbor
end

@testset "TSP 2-opt improvement" begin
    pts = make_pts(12; seed=2)
    nn  = tsp_nn(pts; rng=MersenneTwister(3))
    to  = tsp_two_opt(pts; init_tour=nn.tour, rng=MersenneTwister(4))
    @test to.distance <= nn.distance + 1e-6
    @test to.improvement >= 0.0
    @test to.method == :two_opt
end

@testset "TSP tour validity" begin
    pts = make_pts(15; seed=5)
    res = tsp_two_opt(pts; rng=MersenneTwister(6))
    @test allunique(res.tour)
    @test length(res.tour) == 15
    @test all(1 .<= res.tour .<= 15)
end

@testset "VRP Clarke-Wright basic" begin
    pts   = make_pts(10; seed=7)
    depot = [10.0, 10.0]
    res   = vrp_cw(pts, depot; demands=ones(10), capacity=4.0)
    @test res.n_vehicles >= 1
    @test res.total_distance > 0.0
    @test res.n_customers == 10
    @test sum(length(r) for r in res.routes) == 10
end

@testset "VRP capacity constraints" begin
    pts   = make_pts(8; seed=8)
    depot = [5.0, 5.0]
    dem   = ones(8)
    res   = vrp_cw(pts, depot; demands=dem, capacity=2.0)
    for (r, l) in zip(res.routes, res.capacity_used)
        @test l <= 2.0 + 1e-6
    end
end

@testset "VRP route distance helper" begin
    pts   = make_pts(5; seed=9)
    depot = [0.0, 0.0]
    d     = vrp_route_distance([1,2,3], pts, depot)
    @test d > 0.0
end

@testset "MEXCLP basic" begin
    demand = make_pts(15; seed=10)
    cands  = make_pts(8;  seed=11)
    rng    = MersenneTwister(12)
    res    = mexclp(demand, cands, 3; coverage_radius=6.0, rng=rng)
    @test length(res.facility_locs) == 3
    @test 0.0 <= res.total_expected_coverage <= 1.0
    @test length(res.coverage) == 15
end

@testset "MEXCLP coverage increases with p" begin
    demand = make_pts(20; seed=13)
    cands  = demand
    rng    = MersenneTwister(14)
    r2 = mexclp(demand, cands, 2; coverage_radius=4.0, rng=rng)
    r5 = mexclp(demand, cands, 5; coverage_radius=4.0, rng=rng)
    @test r5.total_expected_coverage >= r2.total_expected_coverage - 1e-6
end

@testset "Dispatch assignment" begin
    incidents = hcat([1.0,5.0,9.0], [1.0,5.0,9.0])
    stations  = hcat([0.0,5.0,10.0],[0.0,5.0,10.0])
    avail     = [1,1,1]
    asgn      = dispatch_assignment(incidents, stations, avail)
    @test length(asgn) == 3
    @test all(1 .<= asgn .<= 3)
end

@testset "Erlang-C formula" begin
    ec = erlang_c(2.0, 1.0, 3)
    @test 0.0 <= ec.p_wait <= 1.0
    @test ec.mean_wait >= 0.0
    @test ec.mean_queue >= 0.0
    @test ec.min_servers >= 1
end

@testset "Erlang-C heavy traffic" begin
    ec = erlang_c(2.9, 1.0, 3)  # ρ = 0.97
    @test ec.p_wait > 0.5  # high wait probability
end

@testset "Routing report" begin
    pts   = make_pts(8; seed=20)
    depot = [5.0, 5.0]
    rng   = MersenneTwister(21)
    rpt   = routing_report(pts, depot; λ=1.5, μ=1.0, c_init=2, rng=rng)
    @test rpt.n_stops == 8
    @test rpt.tsp_2opt_dist <= rpt.tsp_nn_dist + 1e-6
    @test rpt.vrp_routes >= 1
    @test isfinite(rpt.erlang_c_pw)
end
