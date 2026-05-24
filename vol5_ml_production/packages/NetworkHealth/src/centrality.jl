# centrality.jl — Network centrality measures for provider analysis
# Chapter 36.2
#
# Uses Graphs.jl centrality functions where applicable.

"""
    degree_centrality(g; direction=:out, normalize=true) -> Vector{Float64}

Degree centrality: fraction of nodes each provider is connected to.
For directed graphs, uses out-degree by default.
"""
function degree_centrality(g::ReferralNetwork;
                            direction::Symbol = :out,
                            normalize::Bool   = true)
    n  = g.n
    dc = [degree(g, v; direction=direction) for v in 1:n]
    normalize && n > 1 && (dc ./= (n - 1))
    dc
end

"""
    betweenness_centrality(g; normalize=true) -> Vector{Float64}

Betweenness centrality using Graphs.jl's efficient Brandes (2001) implementation.
Counts fraction of shortest paths passing through each node.
"""
function betweenness_centrality(g::ReferralNetwork; normalize::Bool = true)
    # Use Graphs.jl betweenness_centrality on the underlying graph
    # Build a simple digraph (unweighted) for BFS-based betweenness
    dg = Graphs.SimpleDiGraph(g.n)
    for i in 1:g.n
        for j in g.adj[i, :].nzind
            Graphs.add_edge!(dg, i, j)
        end
    end
    bc = Graphs.betweenness_centrality(dg; normalize=normalize)
    bc
end

# BFS helper still needed by flow.jl and access_metrics.jl
function _bfs_single_source(g::ReferralNetwork, s::Int)
    n    = g.n
    dist = fill(Inf, n)
    sigma = zeros(n)
    pred = [Int[] for _ in 1:n]
    dist[s]  = 0.0
    sigma[s] = 1.0

    queue = [s]
    head  = 1
    while head <= length(queue)
        v = queue[head]; head += 1
        for w in g.adj[v, :].nzind
            # First visit
            if dist[w] == Inf
                dist[w] = dist[v] + 1
                push!(queue, w)
            end
            if dist[w] == dist[v] + 1
                sigma[w] += sigma[v]
                push!(pred[w], v)
            end
        end
    end
    dist, sigma, pred
end

"""
    closeness_centrality(g; normalize=true) -> Vector{Float64}

Closeness centrality using Graphs.jl.
"""
function closeness_centrality(g::ReferralNetwork; normalize::Bool = true)
    # Build simple digraph
    dg = Graphs.SimpleDiGraph(g.n)
    for i in 1:g.n
        for j in g.adj[i, :].nzind
            Graphs.add_edge!(dg, i, j)
        end
    end
    Graphs.closeness_centrality(dg; normalize=normalize)
end

"""
    eigenvector_centrality(g; max_iter=100, tol=1e-9) -> Vector{Float64}

Power iteration for eigenvector centrality (dominant eigenvector of A).
High score = connected to well-connected providers.
"""
function eigenvector_centrality(g::ReferralNetwork;
                                 max_iter::Int    = 100,
                                 tol      ::Float64 = 1e-9)
    n = g.n
    x = ones(n) ./ n
    A = g.adj

    for _ in 1:max_iter
        x_new = A * x
        norm_ = maximum(abs, x_new)
        norm_ < 1e-12 && break
        x_new ./= norm_
        maximum(abs, x_new .- x) < tol && break
        x = x_new
    end
    x ./= max(sum(x), 1e-12)
    x
end

"""
    pagerank(g; α=0.85, max_iter=100, tol=1e-9) -> Vector{Float64}

Page & Brin (1999) PageRank using Graphs.jl.
Adapted for provider referral networks: high rank = frequently reached provider.
"""
function pagerank(g::ReferralNetwork;
                  α       ::Float64 = 0.85,
                  max_iter::Int     = 100,
                  tol     ::Float64 = 1e-9)
    # Build simple digraph for Graphs.jl pagerank
    dg = Graphs.SimpleDiGraph(g.n)
    for i in 1:g.n
        for j in g.adj[i, :].nzind
            Graphs.add_edge!(dg, i, j)
        end
    end
    Graphs.pagerank(dg, α; n=max_iter, ε=tol)
end
