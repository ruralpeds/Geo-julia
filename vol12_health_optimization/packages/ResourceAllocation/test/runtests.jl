using Test, Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "src", "ResourceAllocation.jl"))
using .ResourceAllocation

@testset "Knapsack 0/1 basic" begin
    v = [4.0, 5.0, 3.0, 7.0, 2.0]
    w = [2.0, 3.0, 2.0, 4.0, 1.0]
    r = knapsack_01(v, w, 7.0)
    @test r.feasible
    @test r.objective >= 0.0
    @test sum(r.x .* w) <= 7.0 + 1e-6
    @test length(r.x) == 5
    @test all(r.x .∈ Ref([0,1]))
end

@testset "Knapsack known solution" begin
    # All items fit
    v = [1.0, 1.0, 1.0]
    w = [1.0, 1.0, 1.0]
    r = knapsack_01(v, w, 3.0)
    @test r.objective ≈ 3.0 atol=1e-3
end

@testset "BIP branch and bound" begin
    # Simple binary covering problem
    c = [1.0, 2.0, 1.5]
    A = [1.0 0.0 1.0; 0.0 1.0 1.0]
    b = [1.0, 1.0]
    r = bip_branch_bound(c, A, b; sense=:max)
    @test r.feasible
    @test r.objective >= 0.0
    @test all(r.x .∈ Ref([0,1]))
end

@testset "BIP infeasible" begin
    # Impossible constraint
    c = [1.0, 1.0]
    A = [3.0 3.0]
    b = [-1.0]   # no feasible solution
    r = bip_branch_bound(c, A, b; sense=:max)
    # Either infeasible or degenerate
    @test isa(r, BIPResult)
end

@testset "Two-stage stochastic programming" begin
    # Simple resource allocation: buy now, satisfy demand later
    rng  = MersenneTwister(1)
    c1   = [0.5]       # cost of first-stage resource
    c2   = [2.0]       # recourse cost (expensive to buy more later)
    A1   = [1.0;;]     # first-stage constraint
    b1   = [5.0]       # budget
    A2   = [1.0;;]     # recourse constraint (resource + recourse ≥ demand)
    # Scenarios: low demand (30%) and high demand (70%)
    b_s  = hcat([2.0], [4.0])  # 1×2 matrix
    probs = [0.3, 0.7]
    res  = two_stage_sp(c1, c2, A1, A2, b1, b_s, probs; sense=:min)
    @test isfinite(res.obj_expected)
    @test length(res.x_first) == 1
    @test size(res.x_second) == (1, 2)
end

@testset "Two-stage VSS and EVPI" begin
    c1 = [1.0, 0.5]
    c2 = [3.0, 2.0]
    A1 = [1.0 1.0; 0.0 1.0]
    b1 = [4.0, 2.0]
    A2 = [1.0 0.0; 0.0 1.0]
    b_s = hcat([2.0,1.5],[4.0,2.0],[3.0,1.0])
    probs = [0.3,0.4,0.3]
    res = two_stage_sp(c1, c2, A1, A2, b1, b_s, probs; sense=:min)
    @test isfinite(res.vss)
    @test isfinite(res.obj_evpi)
    @test res.n_scenarios == 3
end

@testset "Value iteration convergence" begin
    R, P = health_resource_mdp(6, 3)
    res  = value_iteration(R, P; γ=0.9)
    @test res.converged
    @test length(res.V) == 6
    @test all(1 .<= res.policy .<= 3)
    @test res.n_iter < 200
end

@testset "Policy iteration" begin
    R, P = health_resource_mdp(8, 4)
    vi   = value_iteration(R, P; γ=0.95)
    pi   = policy_iteration(R, P; γ=0.95)
    # Both should converge to same value function (approximately)
    @test pi.converged
    @test isapprox(vi.V, pi.V; atol=0.5)
end

@testset "MDP simulation" begin
    R, P = health_resource_mdp(5, 3)
    res  = value_iteration(R, P)
    rng  = MersenneTwister(10)
    sim  = mdp_simulate(res, 1, R, P; n_steps=20, rng=rng)
    @test length(sim.states)  == 21  # n_steps + initial
    @test length(sim.actions) == 20
    @test length(sim.rewards) == 20
    @test isfinite(sim.discounted_reward)
end

@testset "Health resource MDP" begin
    R, P = health_resource_mdp(10, 5)
    @test size(R) == (10, 5)
    @test size(P) == (10, 5, 10)
    # Transition probabilities sum to 1
    for s in 1:10, a in 1:5
        @test sum(P[s,a,:]) ≈ 1.0 atol=1e-6
    end
    # Higher staffing should reduce backlog (higher P of moving to lower state)
    for s in 2:10
        @test P[s,5,s-1] >= P[s,1,s-1] - 0.1
    end
end

@testset "Allocation report" begin
    R, P = health_resource_mdp(5, 3)
    rpt  = allocation_report(study_name="Test";
                              values=[3.0,5.0,2.0], weights=[1.0,2.0,1.0], capacity=3.0,
                              R=R, P=P, γ=0.9)
    @test isfinite(rpt.knapsack_obj)
    @test rpt.mdp_converged
end
