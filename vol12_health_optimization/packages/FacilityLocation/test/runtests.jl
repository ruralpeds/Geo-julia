using Test, Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "src", "FacilityLocation.jl"))
using .FacilityLocation

function make_pts(n=20; seed=1)
    rng = MersenneTwister(seed)
    hcat(rand(rng, n) .* 10, rand(rng, n) .* 10)
end

@testset "p-median basic" begin
    pts = make_pts(15)
    rng = MersenneTwister(1)
    res = p_median(pts, pts, 3; rng=rng)
    @test length(res.open_facilities) == 3
    @test all(1 .<= res.open_facilities .<= 15)
    @test res.objective >= 0.0
    @test length(res.assignment) == 15
end

@testset "p-median with separate candidates" begin
    demand = make_pts(20; seed=2)
    cands  = make_pts(8;  seed=3)
    rng    = MersenneTwister(4)
    res    = p_median(demand, cands, 3; rng=rng)
    @test length(res.open_facilities) == 3
    @test all(a in 1:8 for a in res.assignment)
end

@testset "p-median improvement" begin
    pts = make_pts(20)
    rng = MersenneTwister(5)
    r1  = p_median(pts, pts, 4; max_iter=1,   rng=rng)
    r2  = p_median(pts, pts, 4; max_iter=500, rng=rng)
    @test r2.objective <= r1.objective + 1e-6
end

@testset "p-median weighted" begin
    pts = make_pts(15)
    w   = rand(MersenneTwister(6), 15)
    rng = MersenneTwister(7)
    res = p_median(pts, pts, 3; weights=w, rng=rng)
    @test isfinite(res.objective)
end

@testset "set cover" begin
    demand = make_pts(20; seed=8)
    cands  = make_pts(10; seed=9)
    res    = set_cover(demand, cands; coverage_radius=3.0)
    @test res.n_facilities >= 0
    @test 0.0 <= res.coverage_fraction <= 1.0
    @test length(res.covered) == 20
end

@testset "set cover 100% with large radius" begin
    pts = make_pts(10; seed=10)
    res = set_cover(pts, pts; coverage_radius=100.0)
    @test res.n_facilities == 1
    @test res.coverage_fraction == 1.0
end

@testset "MCLP basic" begin
    demand = make_pts(25; seed=11)
    cands  = make_pts(12; seed=12)
    rng    = MersenneTwister(13)
    res    = mclp(demand, cands, 3; coverage_radius=2.0, rng=rng)
    @test length(res.open_facilities) == 3
    @test 0.0 <= res.coverage_fraction <= 1.0
    @test res.demand_covered <= res.demand_total
end

@testset "MCLP coverage increases with p" begin
    demand = make_pts(30; seed=14)
    cands  = demand  # candidates = demand sites
    rng    = MersenneTwister(15)
    r2 = mclp(demand, cands, 2; coverage_radius=1.5, rng=rng)
    r5 = mclp(demand, cands, 5; coverage_radius=1.5, rng=rng)
    @test r5.demand_covered >= r2.demand_covered - 1e-6
end

@testset "capacitated FLP" begin
    demand = make_pts(20; seed=16)
    cands  = make_pts(8;  seed=17)
    caps   = fill(sum(ones(20))/3, 8)  # cap = ~1/3 of total demand each
    rng    = MersenneTwister(18)
    res    = cap_flp(demand, cands, 3; capacities=caps, rng=rng)
    @test length(res.open_facilities) == 3
    @test isfinite(res.objective)
    @test length(res.assignment) == 20
end

@testset "catchment voronoi" begin
    demand = make_pts(30; seed=19)
    facs   = make_pts(5;  seed=20)
    cv     = catchment_voronoi(demand, facs)
    @test all(1 .<= cv.assignment .<= 5)
    @test sum(cv.catchment_pop) ≈ cv.total_pop
    @test cv.n_facilities == 5
end

@testset "facility report" begin
    demand = make_pts(15; seed=21)
    cands  = make_pts(8;  seed=22)
    rng    = MersenneTwister(23)
    rpt    = facility_report(demand, cands; p=3, coverage_radius=2.0, rng=rng)
    @test rpt.n_demand == 15
    @test rpt.p == 3
    @test isfinite(rpt.pmedian_obj)
    @test 0.0 <= rpt.mclp_coverage <= 1.0
end
