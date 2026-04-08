using Test, Random, DataFrames, SparseArrays
Random.seed!(42)

import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using NetworkHealth

# ── Fixtures ──────────────────────────────────────────────────────────────────

# 10-node ring with some cross-edges
function make_ring_network(n=10)
    Is = Int[]; Js = Int[]; Vs = Float64[]
    for i in 1:n
        j = mod(i, n) + 1
        push!(Is, i, j); push!(Js, j, i); push!(Vs, 1.0, 1.0)
    end
    # Add 2 shortcuts
    push!(Is, 1, 6); push!(Js, 6, 1); push!(Vs, 2.0, 2.0)
    A = sparse(Is, Js, Vs, n, n)
    from_adjmatrix(A; directed=true)
end

# Small triangle
function make_triangle()
    A = Float64[0 2 0; 0 0 3; 1 0 0]
    from_adjmatrix(A; directed=true)
end

# Random sparse network
function make_random_net(n=20, density=0.15; rng=MersenneTwister(42))
    A = zeros(n, n)
    for i in 1:n, j in 1:n
        i != j && rand(rng) < density && (A[i,j] = rand(rng) * 10)
    end
    from_adjmatrix(A; directed=true)
end

g_ring = make_ring_network(10)
g_tri  = make_triangle()
g_rand = make_random_net(15)

@testset "NetworkHealth Tests" begin

    @testset "1. Graph construction — from_adjmatrix" begin
        @test nv(g_ring) == 10
        @test ne(g_ring) > 0
        @test g_ring.directed == true
    end

    @testset "2. Graph construction — from_dataframe" begin
        edf = DataFrame(src=[1,2,3,1], dst=[2,3,1,3], weight=[1.0,2.0,3.0,0.5])
        g   = from_dataframe(edf; src_col=:src, dst_col=:dst, weight_col=:weight)
        @test nv(g) == 3
        @test ne(g) == 4
    end

    @testset "3. neighbors" begin
        nbrs = neighbors(g_ring, 1; direction=:out)
        @test !isempty(nbrs)
        @test all(1 .<= nbrs .<= 10)
    end

    @testset "4. degree" begin
        d = degree(g_ring, 1; direction=:out)
        @test d > 0
    end

    @testset "5. degree_centrality" begin
        dc = degree_centrality(g_ring; normalize=true)
        @test length(dc) == 10
        @test all(dc .>= 0)
        @test maximum(dc) <= 1.0 + 1e-9
    end

    @testset "6. betweenness_centrality" begin
        bc = betweenness_centrality(g_ring; normalize=true)
        @test length(bc) == 10
        @test all(bc .>= 0)
        # The shortcut nodes (1, 6) should have high betweenness
        @test bc[1] > minimum(bc)
    end

    @testset "7. closeness_centrality" begin
        cc = closeness_centrality(g_ring; normalize=true)
        @test length(cc) == 10
        @test all(cc .>= 0)
    end

    @testset "8. eigenvector_centrality" begin
        ec = eigenvector_centrality(g_ring; max_iter=50)
        @test length(ec) == 10
        @test all(ec .>= 0)
        @test abs(sum(ec) - 1.0) < 1e-6
    end

    @testset "9. pagerank" begin
        pr = pagerank(g_ring; α=0.85)
        @test length(pr) == 10
        @test all(pr .> 0)
        @test abs(sum(pr) - 1.0) < 1e-6
    end

    @testset "10. label_propagation" begin
        labels = label_propagation(g_ring; max_iter=50)
        @test length(labels) == 10
        @test all(labels .>= 1)
        @test length(unique(labels)) >= 1
    end

    @testset "11. louvain_communities" begin
        labels = louvain_communities(g_rand; max_iter=50)
        @test length(labels) == nv(g_rand)
        @test all(labels .>= 1)
        @test length(unique(labels)) >= 1
    end

    @testset "12. max_flow_bfs" begin
        # Triangle: max flow from 1→3
        flow = max_flow_bfs(g_tri, 1, 3)
        @test flow > 0
        @test flow <= 6.0  # path 1→2→3 has min capacity 2
    end

    @testset "13. referral_concentration" begin
        rc = referral_concentration(g_ring)
        @test length(rc) == 10
        @test all(0 .<= rc .<= 1.0 + 1e-9)
    end

    @testset "14. herfindahl_index" begin
        # Equal market shares
        hhi_equal = herfindahl_index([1.0, 1.0, 1.0, 1.0])
        @test hhi_equal ≈ 0.25 atol=1e-9
        # Monopoly
        hhi_mono = herfindahl_index([1.0, 0.0, 0.0, 0.0])
        @test hhi_mono ≈ 1.0 atol=1e-9
    end

    @testset "15. shortest_paths" begin
        d = shortest_paths(g_ring, 1)
        @test length(d) == 10
        @test d[1] == 0.0
        @test all(d .>= 0)
    end

    @testset "16. diameter + average_path_length" begin
        diam = diameter(g_ring)
        @test diam > 0
        @test isfinite(diam)
        apl = average_path_length(g_ring)
        @test 0 < apl <= diam
    end

    @testset "17. fragmentation_index" begin
        # Fully connected ring: fragmentation should be low
        f = fragmentation_index(g_ring)
        @test 0 <= f <= 1

        # Disconnected: two isolated nodes
        A2 = zeros(4, 4); A2[1,2] = 1; A2[3,4] = 1
        g2 = from_adjmatrix(A2; directed=true)
        @test fragmentation_index(g2) > 0
    end

    @testset "18. network_access_score" begin
        county_nodes = [[1,2], [3,4,5], Int[], [6]]
        scores = network_access_score(g_ring, county_nodes; centrality=:pagerank)
        @test length(scores) == 4
        @test scores[3] == 0.0  # empty county
        @test all(scores .>= 0)
    end

    @testset "19. isolation_index" begin
        group_a = [1, 2, 3]
        group_b = [7, 8, 9, 10]
        idx = isolation_index(g_ring, group_a, group_b)
        @test 0 <= idx <= 1
    end

    @testset "20. summarize" begin
        s = summarize(g_ring)
        @test s isa NetworkSummary
        @test s.n_nodes == 10
        @test s.n_edges == ne(g_ring)
        @test 0 <= s.density <= 1
        @test s.n_communities >= 1
    end

end  # @testset

@info "NetworkHealth tests complete."
