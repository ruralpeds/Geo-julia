# centrality.jl — Network centrality measures for provider analysis
# Chapter 36.2

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

Brandes (2001) algorithm for betweenness centrality.
Counts fraction of shortest paths passing through each node.

O(VE) for unweighted; O(VE + V²log V) for weighted (Dijkstra).
"""
function betweenness_centrality(g::ReferralNetwork; normalize::Bool = true)
    n  = g.n
    bc = zeros(n)

    for s in 1:n
        # BFS/Dijkstra from source s
        dist, sigma, pred = _bfs_single_source(g, s)

        # Accumulate pair dependencies
        delta = zeros(n)
        order = sortperm(dist; rev=true)  # process in reverse BFS order
        for w in order
            dist[w] == Inf && continue
            for v in pred[w]
                coeff = (sigma[v] / sigma[w]) * (1.0 + delta[w])
                delta[v] += coeff
            end
            w != s && (bc[w] += delta[w])
        end
    end

    if normalize && n > 2
        denom = g.directed ? Float64((n-1)*(n-2)) : Float64((n-1)*(n-2)/2)
        bc ./= denom
    end
    bc
end

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

Closeness centrality: reciprocal of mean shortest path length.
Normalised by reachable fraction for disconnected graphs.
"""
function closeness_centrality(g::ReferralNetwork; normalize::Bool = true)
    n  = g.n
    cc = zeros(n)
    for s in 1:n
        dist, _, _ = _bfs_single_source(g, s)
        reachable   = count(d -> d < Inf && d > 0, dist)
        reachable == 0 && continue
        total_dist   = sum(d for d in dist if d < Inf && d > 0)
        raw          = reachable / max(total_dist, 1.0)
        cc[s]        = normalize ? raw * (reachable / (n-1)) : raw
    end
    cc
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

Page & Brin (1999) PageRank with damping factor α.
Adapted for provider referral networks: high rank = frequently reached provider.

Transition matrix: M = α·D⁻¹A + (1-α)/n · 1·1'
where D = out-degree diagonal.
"""
function pagerank(g::ReferralNetwork;
                  α       ::Float64 = 0.85,
                  max_iter::Int     = 100,
                  tol     ::Float64 = 1e-9)
    n   = g.n
    A   = g.adj
    out = vec(sum(A; dims=2))
    # Row-normalise (stochastic matrix)
    D_inv = spdiagm(0 => [d > 0 ? 1/d : 0.0 for d in out])
    M     = D_inv * A

    r = ones(n) ./ n
    dangling = findall(out .== 0)

    for _ in 1:max_iter
        # Handle dangling nodes: distribute their mass uniformly
        dangling_contrib = isempty(dangling) ? 0.0 : α * sum(r[dangling]) / n
        r_new = α .* (M' * r) .+ dangling_contrib .+ (1-α) / n
        r_new ./= max(sum(r_new), 1e-12)
        maximum(abs, r_new .- r) < tol && break
        r = r_new
    end
    r
end
