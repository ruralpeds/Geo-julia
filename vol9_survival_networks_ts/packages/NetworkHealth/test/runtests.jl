using Test, Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "src", "NetworkHealth.jl"))
using .NetworkHealth

function make_ring_graph(n=8)
    W = zeros(n, n)
    for i in 1:n; W[i, mod1(i+1, n)] = 1.0; end
    build_graph(W; labels=["N$i" for i in 1:n])
end

function make_flow_matrix(n=5; seed=1)
    rng = MersenneTwister(seed)
    F   = abs.(randn(rng, n, n)) .* 50
    for i in 1:n; F[i,i] = abs(randn(rng)) * 200; end  # self-treat
    F
end

@testset "HealthGraph — build_graph" begin
    W = [0.0 1.0 0.0; 0.0 0.0 2.0; 0.5 0.0 0.0]
    g = build_graph(W)
    @test g.n == 3
    @test length(g.adj[1]) == 1
    @test g.adj[1][1] == (2, 1.0)
    @test g.weight_matrix ≈ W
end

@testset "HealthGraph — degree centrality" begin
    g = make_ring_graph(8)
    dc = degree_centrality(g; mode=:out)
    @test all(dc .≈ 1.0/7.0)  # each node has exactly 1 out-edge
    dc_in = degree_centrality(g; mode=:in)
    @test all(dc_in .≈ 1.0/7.0)
end

@testset "HealthGraph — strength centrality" begin
    W = [0.0 3.0; 1.0 0.0]
    g = build_graph(W)
    s = strength_centrality(g; mode=:out)
    @test s[1] ≈ 3.0
    @test s[2] ≈ 1.0
end

@testset "HealthGraph — BFS" begin
    g = make_ring_graph(5)
    d, p = bfs(g, 1)
    @test d[1] == 0.0
    @test all(d .>= 0.0)
    @test d[2] == 1.0   # adjacent in ring
end

@testset "HealthGraph — Dijkstra" begin
    W = [0.0 1.0 4.0; 0.0 0.0 2.0; 0.0 0.0 0.0]
    g = build_graph(W)
    d, _ = dijkstra(g, 1)
    @test d[1] ≈ 0.0
    @test d[2] ≈ 1.0
    @test d[3] ≈ 3.0   # 1→2→3 = 3 < 1→3 = 4
end

@testset "HealthGraph — betweenness centrality" begin
    # Path graph: 1-2-3-4, node 2 and 3 are on all paths
    W = zeros(4, 4)
    W[1,2]=W[2,3]=W[3,4]=1.0
    g  = build_graph(W)
    bc = betweenness_centrality(g)
    @test length(bc) == 4
    @test all(bc .>= 0.0)
end

@testset "HealthGraph — PageRank" begin
    g = make_ring_graph(5)
    pr = pagerank(g)
    @test length(pr) == 5
    @test sum(pr) ≈ 1.0 atol=1e-8
    @test all(pr .>= 0.0)
    # Symmetric ring: equal PageRank
    @test all(abs.(pr .- pr[1]) .< 1e-6)
end

@testset "HealthGraph — clustering coefficient" begin
    # Triangle: all nodes connected
    W = [0.0 1.0 1.0; 1.0 0.0 1.0; 1.0 1.0 0.0]
    g = build_graph(W)
    cc, gcc = clustering_coefficient(g)
    @test all(cc .≈ 1.0)
    @test gcc ≈ 1.0
end

@testset "HealthGraph — weakly connected components" begin
    # Two disconnected components
    W = zeros(6, 6)
    W[1,2]=W[2,3]=1.0; W[4,5]=W[5,6]=1.0
    g = build_graph(W)
    comps = weakly_connected_components(g)
    @test length(comps) == 2
    @test sort(vcat(comps...)) == 1:6
end

@testset "SIR model — basic conservation" begin
    r = sir_model(10000, 10; β=0.3, γ=0.1)
    @test r.R0 ≈ 3.0
    # S+I+R ≈ 1 at all times
    total = r.S .+ r.I .+ r.R
    @test all(abs.(total .- 1.0) .< 0.01)
    @test r.S[end] <= r.S[1]   # S non-increasing
    @test r.R[end] >= r.R[1]   # R non-decreasing
    @test r.peak_I > 0.0
end

@testset "SIR model — R₀ < 1 no epidemic" begin
    r = sir_model(10000, 10; β=0.05, γ=0.2)
    @test r.R0 < 1.0
    @test r.peak_I < 0.01   # negligible spread
end

@testset "SEIR model" begin
    r = seir_model(10000, 20, 5; β=0.35, σ=0.2, γ=0.1)
    @test r.R0 ≈ 3.5 atol=0.1
    total = r.S .+ r.E .+ r.I .+ r.R
    @test all(abs.(total .- 1.0) .< 0.01)
    @test 0.0 < r.herd_threshold < 1.0
    @test r.peak_time > 0.0
end

@testset "SEIRD model" begin
    r = seird_model(10000; β=0.3, σ=0.2, γ=0.09, μ=0.01)
    @test 0.0 < r.ifr < 1.0
    total = r.S .+ r.E .+ r.I .+ r.R .+ r.D
    @test all(abs.(total .- 1.0) .< 0.01)
    @test r.D[end] > 0.0   # some deaths occurred
end

@testset "estimate_r0" begin
    # Exponential growth phase
    inc = [1.0 * 1.3^t for t in 0:9]
    res = estimate_r0(inc; method=:exponential_growth, γ=0.1, n_points=8)
    @test isfinite(res.R0)
    @test res.R0 > 1.0
end

@testset "Network SIR" begin
    rng = MersenneTwister(42)
    g   = make_ring_graph(10)
    res = network_sir(g, [1]; β=0.3, γ=0.1, n_steps=50, n_sims=20, rng=rng)
    @test length(res.times) == 51
    @test all(0.0 .<= res.I_mean .<= 1.0)
    @test all(res.S_mean .+ res.I_mean .+ res.R_mean .<= 1.0 + 1e-8)
end

@testset "Patient flow analysis" begin
    F  = make_flow_matrix(4)
    pf = patient_flow_analysis(F)
    @test pf.n_facilities == 4
    @test all(pf.self_sufficiency .>= 0.0)
    @test all(pf.self_sufficiency .<= 1.0)
    @test all(pf.referral_rate .>= 0.0)
end

@testset "Catchment area (E2SFCA)" begin
    pop      = [1000.0, 2000.0, 800.0]
    capacity = [50.0, 80.0]
    dist     = [2.0 10.0; 5.0 3.0; 1.0 8.0]
    ca = catchment_area(pop, capacity, dist)
    @test length(ca.assignment) == 3
    @test all(1 .<= ca.assignment .<= 2)
    @test sum(ca.catchment_pop) ≈ sum(pop)
end

@testset "Referral centrality" begin
    F  = make_flow_matrix(5)
    pf = patient_flow_analysis(F)
    rc = referral_centrality(pf)
    @test length(rc.pagerank) == 5
    @test sum(rc.pagerank) ≈ 1.0 atol=1e-8
    @test length(rc.betweenness) == 5
end

@testset "Network vulnerability" begin
    rng = MersenneTwister(1)
    W   = abs.(randn(rng, 8, 8)) .* (rand(rng, 8, 8) .> 0.5)
    for i in 1:8; W[i,i]=0.0; end
    g   = build_graph(W)
    vul = network_vulnerability(g; n_removals=3)
    @test length(vul) == 3
    @test all(r.largest_component >= 0 for r in vul)
end

@testset "Network report" begin
    g = make_ring_graph(6)
    r_sir = sir_model(1000, 5; β=0.3, γ=0.1)
    rpt   = network_report(g, r_sir; model_name="TestNet")
    @test isa(rpt, NetworkReport)
    @test rpt.n_facilities == 6
    @test isfinite(rpt.graph_density)
    @test isfinite(rpt.epidemic_r0)
end
