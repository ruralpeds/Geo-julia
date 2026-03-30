#!/usr/bin/env julia
# test/runtests.jl — TestUtils package unit tests

using Test, Random

include(joinpath(@__DIR__, "..", "src", "TestUtils.jl"))
using .TestUtils

# ─── Generator tests ─────────────────────────────────────────────────────────

@testset "gen_uniform_pts" begin
    rng = MersenneTwister(1)
    pts = gen_uniform_pts(20; rng=rng)
    @test size(pts) == (20, 2)
    @test all(0.0 .<= pts[:, 1] .<= 7.6)
    @test all(0.0 .<= pts[:, 2] .<= 3.1)

    # deterministic with same seed
    pts2 = gen_uniform_pts(20; rng=MersenneTwister(1))
    @test pts == pts2
end

@testset "gen_clustered_pts" begin
    pts = gen_clustered_pts(50; rng=MersenneTwister(2), n_clusters=4)
    @test size(pts) == (50, 2)
    @test all(0.0 .<= pts[:, 1] .<= 7.6)
    @test all(0.0 .<= pts[:, 2] .<= 3.1)
end

@testset "gen_grid_pts" begin
    pts = gen_grid_pts(4, 5)
    @test size(pts) == (20, 2)
    @test pts[1, 1] ≈ 0.0
    @test pts[end, 1] ≈ 7.6
    @test pts[1, 2] ≈ 0.0
    @test pts[end, 2] ≈ 3.1
end

@testset "gen_weights" begin
    w = gen_weights(10; rng=MersenneTwister(3))
    @test length(w) == 10
    @test all(w .>= 500.0)
    @test all(w .<= 5500.0)

    @test all(gen_unit_weights(5) .== 1.0)
end

@testset "gen_nd_scenario" begin
    sc = gen_nd_scenario(; rng=MersenneTwister(4), n_demand=20, n_cand=12)
    @test size(sc.demand_pts) == (20, 2)
    @test size(sc.cand_pts)   == (12, 2)
    @test length(sc.weights)  == 20
    @test all(sc.weights .> 0)
    @test size(sc.depot) == (1, 2)
end

@testset "gen_resource_problem" begin
    p = gen_resource_problem(8; rng=MersenneTwister(5))
    @test length(p.values)  == 8
    @test length(p.weights) == 8
    @test all(p.values  .> 0)
    @test all(p.weights .> 0)
    @test p.capacity ≈ sum(p.weights) / 2
end

@testset "gen_mdp" begin
    m = gen_mdp(6, 3; rng=MersenneTwister(6))
    @test size(m.R) == (6, 3)
    @test size(m.P) == (3, 6, 6)
    @test m.γ == 0.95
    # Each row of each transition matrix sums to 1
    for a in 1:3, s in 1:6
        @test sum(m.P[a, s, :]) ≈ 1.0 atol=1e-12
    end
end

@testset "gen_tsp_tour" begin
    t = gen_tsp_tour(10; rng=MersenneTwister(7))
    @test size(t.pts) == (10, 2)
    @test t.lb > 0
end

# ─── Metrics tests ───────────────────────────────────────────────────────────

@testset "ResultStore and TestOutcome" begin
    store = ResultStore()
    @test isempty(store.outcomes)

    o1 = TestOutcome("test_A", "file1.jl", 10, 0, 0, 0.05)
    o2 = TestOutcome("test_B", "file2.jl", 8, 2, 0, 0.10)
    o3 = TestOutcome("test_C", "file3.jl", 5, 0, 1, 0.20; msg="NaN in output")
    push!(store, o1); push!(store, o2); push!(store, o3)

    @test length(store.outcomes) == 3
    @test status(o1) == :pass
    @test status(o2) == :fail
    @test status(o3) == :fail
end

@testset "summary" begin
    store = ResultStore()
    # Empty store
    s = summary(store)
    @test s.total == 0

    push!(store, TestOutcome("p", "f.jl", 5, 0, 0, 0.1))
    push!(store, TestOutcome("q", "f.jl", 3, 1, 0, 0.2))
    s = summary(store)
    @test s.total   == 2
    @test s.passed  == 1
    @test s.failed  == 1
    @test s.pass_rate ≈ 0.5
    @test s.total_assertions == 9
    @test s.total_failures   == 1
    @test s.slowest == "q"
    @test s.fastest == "p"
end

@testset "failed_outcomes / passed_outcomes" begin
    store = ResultStore()
    push!(store, TestOutcome("p", "f.jl", 5, 0, 0, 0.1))
    push!(store, TestOutcome("q", "f.jl", 3, 1, 0, 0.2))
    @test length(failed_outcomes(store)) == 1
    @test length(passed_outcomes(store)) == 1
    @test failed_outcomes(store)[1].name == "q"
end

@testset "categorise_failure" begin
    @test categorise_failure("NaN in output")          == :numerical
    @test categorise_failure("did not converge")       == :convergence
    @test categorise_failure("DimensionMismatch")      == :dimension
    @test categorise_failure("infeasible problem")     == :infeasibility
    @test categorise_failure("completely unrelated")   == :unknown
end

@testset "categorise_outcome" begin
    pass_o = TestOutcome("p", "f.jl", 5, 0, 0, 0.1)
    @test categorise_outcome(pass_o) == :pass

    fail_o = TestOutcome("q", "f.jl", 3, 1, 0, 0.2; msg="NaN detected")
    @test categorise_outcome(fail_o) == :numerical
end

@testset "detect_regressions" begin
    baseline = ResultStore()
    push!(baseline, TestOutcome("A", "f.jl", 5, 0, 0, 0.1))
    push!(baseline, TestOutcome("B", "f.jl", 5, 0, 0, 0.1))

    current = ResultStore()
    push!(current, TestOutcome("A", "f.jl", 5, 0, 0, 0.1))  # still passes
    push!(current, TestOutcome("B", "f.jl", 3, 2, 0, 0.2))  # now fails

    regs = detect_regressions(current, baseline)
    @test "B" in regs
    @test !("A" in regs)
end

println("\n✓ All TestUtils unit tests passed.")
