# graph.jl — Healthcare graph primitives
# HealthGraph, degree centrality, betweenness, PageRank, BFS/DFS

using Statistics, LinearAlgebra

# ── Graph struct ──────────────────────────────────────────────────────────────

"""
    HealthGraph

Weighted directed graph for healthcare facility networks.

Fields:
- `n`      : number of nodes
- `adj`    : adjacency list (node → [(neighbour, weight)])
- `labels` : node labels (facility names, etc.)
- `node_type` : node type vector (e.g. "hospital", "clinic", ...)
- `weights_matrix` : dense weight matrix (n×n), 0 = no edge
"""
struct HealthGraph
    n            ::Int
    adj          ::Vector{Vector{Tuple{Int,Float64}}}  # adj[i] = [(j, w), ...]
    labels       ::Vector{String}
    node_type    ::Vector{String}
    weight_matrix::Matrix{Float64}
end

"""
    build_graph(W; labels, node_type) -> HealthGraph

Construct a HealthGraph from a weight matrix W (n×n).
W[i,j] > 0 implies a directed edge i→j with that weight.
"""
function build_graph(W::AbstractMatrix;
                     labels   ::Vector{String}=["node$i" for i in 1:size(W,1)],
                     node_type::Vector{String}=fill("facility", size(W,1)))
    n   = size(W, 1)
    @assert size(W, 2) == n
    adj = [Vector{Tuple{Int,Float64}}() for _ in 1:n]
    for i in 1:n, j in 1:n
        W[i,j] > 0 && push!(adj[i], (j, Float64(W[i,j])))
    end
    HealthGraph(n, adj, labels, node_type, Float64.(W))
end

# ── Degree centrality ─────────────────────────────────────────────────────────

"""
    degree_centrality(g; mode=:out) -> Vector{Float64}

Compute degree centrality for each node.
`mode ∈ {:in, :out, :total}`
"""
function degree_centrality(g::HealthGraph; mode::Symbol=:out)
    n = g.n
    d = zeros(n)
    if mode == :out || mode == :total
        for i in 1:n; d[i] += length(g.adj[i]); end
    end
    if mode == :in || mode == :total
        for i in 1:n, (j, _) in g.adj[i]; d[j] += 1.0; end
    end
    # Normalise by n-1
    n > 1 ? d ./ (n - 1) : d
end

"""
    strength_centrality(g; mode=:out) -> Vector{Float64}

Weighted degree (strength) centrality.
"""
function strength_centrality(g::HealthGraph; mode::Symbol=:out)
    n = g.n
    s = zeros(n)
    if mode == :out || mode == :total
        for i in 1:n, (_, w) in g.adj[i]; s[i] += w; end
    end
    if mode == :in || mode == :total
        for i in 1:n, (j, w) in g.adj[i]; s[j] += w; end
    end
    s
end

# ── BFS / Shortest paths ───────────────────────────────────────────────────────

"""
    bfs(g, source) -> (dist, parent)

BFS from `source` on the unweighted graph. dist[i] = Inf if unreachable.
"""
function bfs(g::HealthGraph, source::Int)
    dist   = fill(Inf, g.n)
    parent = fill(0,   g.n)
    dist[source] = 0.0
    queue  = [source]
    head   = 1
    while head <= length(queue)
        u = queue[head]; head += 1
        for (v, _) in g.adj[u]
            if isinf(dist[v])
                dist[v]   = dist[u] + 1.0
                parent[v] = u
                push!(queue, v)
            end
        end
    end
    dist, parent
end

"""
    dijkstra(g, source) -> (dist, parent)

Dijkstra's shortest-path from `source` (min-heap via sorted vector).
"""
function dijkstra(g::HealthGraph, source::Int)
    dist   = fill(Inf, g.n)
    parent = fill(0,   g.n)
    visited= falses(g.n)
    dist[source] = 0.0
    # Simple O(n²) implementation (adequate for small graphs)
    for _ in 1:g.n
        # Pick unvisited node with smallest dist
        u = 0; best = Inf
        for i in 1:g.n
            if !visited[i] && dist[i] < best
                best = dist[i]; u = i
            end
        end
        u == 0 && break
        visited[u] = true
        for (v, w) in g.adj[u]
            if dist[u] + w < dist[v]
                dist[v]   = dist[u] + w
                parent[v] = u
            end
        end
    end
    dist, parent
end

# ── Betweenness centrality ────────────────────────────────────────────────────

"""
    betweenness_centrality(g; normalise=true) -> Vector{Float64}

Brandes (2001) betweenness centrality. O(VE) on unweighted graph.
"""
function betweenness_centrality(g::HealthGraph; normalise::Bool=true)
    n  = g.n
    CB = zeros(n)

    for s in 1:n
        # BFS from s
        stack   = Int[]
        pred    = [Int[] for _ in 1:n]
        sigma   = zeros(n)
        dist_s  = fill(-1, n)
        sigma[s] = 1.0
        dist_s[s] = 0
        queue  = [s]
        head   = 1
        while head <= length(queue)
            v = queue[head]; head += 1
            push!(stack, v)
            for (w, _) in g.adj[v]
                if dist_s[w] < 0
                    dist_s[w] = dist_s[v] + 1
                    push!(queue, w)
                end
                if dist_s[w] == dist_s[v] + 1
                    sigma[w] += sigma[v]
                    push!(pred[w], v)
                end
            end
        end
        # Back-propagation
        δ = zeros(n)
        while !isempty(stack)
            w = pop!(stack)
            for v in pred[w]
                σ_ratio = sigma[v] / max(sigma[w], 1e-10)
                δ[v] += σ_ratio * (1.0 + δ[w])
            end
            w != s && (CB[w] += δ[w])
        end
    end

    if normalise && n > 2
        factor = 1.0 / ((n-1)*(n-2))
        CB .*= factor
    end
    CB
end

# ── PageRank ──────────────────────────────────────────────────────────────────

"""
    pagerank(g; d=0.85, max_iter=100, tol=1e-8) -> Vector{Float64}

Power-iteration PageRank. d = damping factor (Brin & Page 1998).
"""
function pagerank(g::HealthGraph; d::Float64=0.85,
                  max_iter::Int=100, tol::Float64=1e-8)
    n  = g.n
    pr = fill(1.0/n, n)

    # Outgoing degree for normalisation
    out_deg = [sum(w for (_, w) in g.adj[i]; init=0.0) for i in 1:n]

    for _ in 1:max_iter
        pr_new = fill((1.0 - d) / n, n)
        for i in 1:n
            out_deg[i] == 0.0 && continue
            for (j, w) in g.adj[i]
                pr_new[j] += d * pr[i] * w / out_deg[i]
            end
        end
        # Dangling nodes: redistribute evenly
        total_dangling = sum(pr[i] for i in 1:n if out_deg[i] == 0.0)
        pr_new .+= d * total_dangling / n

        if maximum(abs.(pr_new .- pr)) < tol
            pr = pr_new; break
        end
        pr = pr_new
    end
    pr ./ sum(pr)  # normalise to sum=1
end

# ── Clustering coefficient ────────────────────────────────────────────────────

"""
    clustering_coefficient(g) -> (local_cc, global_cc)

Local clustering coefficient for each node and global average.
"""
function clustering_coefficient(g::HealthGraph)
    n  = g.n
    cc = zeros(n)
    for i in 1:n
        nbrs = [j for (j, _) in g.adj[i]]
        k    = length(nbrs)
        k < 2 && continue
        edges = 0
        for a in nbrs, b in nbrs
            a == b && continue
            if any(j == b for (j, _) in g.adj[a]); edges += 1; end
        end
        cc[i] = edges / (k * (k - 1))
    end
    cc, mean(cc)
end

# ── Connected components ──────────────────────────────────────────────────────

"""
    weakly_connected_components(g) -> Vector{Vector{Int}}

Weakly connected components (treating directed edges as undirected).
"""
function weakly_connected_components(g::HealthGraph)
    comp   = fill(0, g.n)
    comp_id = 0
    for start in 1:g.n
        comp[start] != 0 && continue
        comp_id += 1
        queue = [start]; head = 1
        comp[start] = comp_id
        while head <= length(queue)
            u = queue[head]; head += 1
            for (v, _) in g.adj[u]
                if comp[v] == 0
                    comp[v] = comp_id
                    push!(queue, v)
                end
            end
            # Also traverse reverse edges (undirected treatment)
            for i in 1:g.n
                if comp[i] == 0 && any(j == u for (j, _) in g.adj[i])
                    comp[i] = comp_id
                    push!(queue, i)
                end
            end
        end
    end
    [findall(comp .== k) for k in 1:comp_id]
end
