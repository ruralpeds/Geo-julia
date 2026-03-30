# graph.jl — ReferralNetwork data structure
# Chapter 36.1

"""
    ReferralNetwork

Directed, weighted healthcare provider referral graph.

Fields:
- `n`        — number of nodes (providers)
- `m`        — number of edges (referral relationships)
- `adj`      — (n × n) sparse adjacency matrix of referral volumes
- `node_attr`— DataFrame with node attributes (id, name, type, lat, lon, ...)
- `directed` — true for directed referral flows
"""
struct ReferralNetwork
    n        ::Int
    m        ::Int
    adj      ::SparseMatrixCSC{Float64,Int}
    node_attr::DataFrame
    directed ::Bool
end

nv(g::ReferralNetwork) = g.n
ne(g::ReferralNetwork) = g.m

"""
    from_dataframe(edges_df; src_col, dst_col, weight_col, node_df, directed) -> ReferralNetwork

Build a ReferralNetwork from an edge-list DataFrame.

`edges_df` must have columns `src_col` and `dst_col` (integer node IDs, 1-indexed).
Optional `weight_col` gives edge weight; defaults to 1.0.
"""
function from_dataframe(edges_df   ::DataFrame;
                        src_col    ::Symbol = :src,
                        dst_col    ::Symbol = :dst,
                        weight_col ::Union{Symbol,Nothing} = :weight,
                        node_df    ::Union{DataFrame,Nothing} = nothing,
                        directed   ::Bool = true)
    src = Int.(edges_df[!, src_col])
    dst = Int.(edges_df[!, dst_col])
    n   = max(maximum(src), maximum(dst))
    wts = isnothing(weight_col) || !hasproperty(edges_df, weight_col) ?
          ones(nrow(edges_df)) : Float64.(edges_df[!, weight_col])

    adj = sparse(src, dst, wts, n, n)
    if !directed
        adj = adj + adj'
        # Fix double-counted diagonal
        adj[diagind(adj)] ./= 2
    end

    attr = isnothing(node_df) ? DataFrame(id=1:n) : node_df
    ReferralNetwork(n, nnz(adj), adj, attr, directed)
end

"""
    from_adjmatrix(A; node_df, directed) -> ReferralNetwork

Build from an adjacency matrix (dense or sparse).
"""
function from_adjmatrix(A::AbstractMatrix;
                        node_df  ::Union{DataFrame,Nothing} = nothing,
                        directed ::Bool = true)
    n   = size(A, 1)
    adj = sparse(Float64.(A))
    m   = nnz(adj)
    attr = isnothing(node_df) ? DataFrame(id=1:n) : node_df
    ReferralNetwork(n, m, adj, attr, directed)
end

"""
    neighbors(g, v; direction=:out) -> Vector{Int}

Return out-neighbors (:out), in-neighbors (:in), or both (:all).
"""
function neighbors(g::ReferralNetwork, v::Int; direction::Symbol = :out)
    direction == :out && return g.adj[v, :].nzind
    direction == :in  && return g.adj[:, v].nzind
    union(g.adj[v, :].nzind, g.adj[:, v].nzind)
end

"""
    degree(g, v; direction=:out) -> Float64

Weighted degree (sum of edge weights).
"""
function degree(g::ReferralNetwork, v::Int; direction::Symbol = :out)
    direction == :out && return sum(g.adj[v, :])
    direction == :in  && return sum(g.adj[:, v])
    sum(g.adj[v, :]) + sum(g.adj[:, v])
end

function Base.show(io::IO, g::ReferralNetwork)
    dir = g.directed ? "Directed" : "Undirected"
    print(io, "ReferralNetwork($dir, n=$(g.n), m=$(g.m))")
end
