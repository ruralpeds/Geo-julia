# nearest.jl — Nearest neighbour statistics

using NearestNeighbors

"""
    nndist(pp) -> Vector{Float64}

Nearest-neighbour distances for all events in the pattern.
"""
function nndist(pp::PointPattern)::Vector{Float64}
    n = pp.n
    n < 2 && error("Need at least 2 points")
    pts  = Float64.(hcat(pp.x, pp.y)')
    tree = KDTree(pts)
    d = Vector{Float64}(undef, n)
    for i in 1:n
        _, dists = knn(tree, pts[:, i], 2, true)
        d[i] = dists[2]
    end
    d
end

"""
    nnwhich(pp) -> Vector{Int}

For each event, return the index of its nearest neighbour.
"""
function nnwhich(pp::PointPattern)::Vector{Int}
    n = pp.n
    n < 2 && error("Need at least 2 points")
    pts  = Float64.(hcat(pp.x, pp.y)')
    tree = KDTree(pts)
    which = Vector{Int}(undef, n)
    for i in 1:n
        idxs, _ = knn(tree, pts[:, i], 2, true)
        which[i] = idxs[2]
    end
    which
end

"""
    pairdist(pp) -> Matrix{Float64}

All pairwise distances between events (n × n symmetric matrix).
Warning: O(n²) — use only for small patterns (n < 5000).
"""
function pairdist(pp::PointPattern)::Matrix{Float64}
    n   = pp.n
    D   = Matrix{Float64}(undef, n, n)
    for i in 1:n
        D[i, i] = 0.0
        for j in (i+1):n
            d = sqrt((pp.x[i]-pp.x[j])^2 + (pp.y[i]-pp.y[j])^2)
            D[i, j] = d
            D[j, i] = d
        end
    end
    D
end

"""
    crossdist(pp1, pp2) -> Matrix{Float64}

Distances from each event in pp1 to each event in pp2 (n1 × n2 matrix).
"""
function crossdist(pp1::PointPattern, pp2::PointPattern)::Matrix{Float64}
    n1, n2 = pp1.n, pp2.n
    D = Matrix{Float64}(undef, n1, n2)
    for i in 1:n1
        for j in 1:n2
            D[i, j] = sqrt((pp1.x[i]-pp2.x[j])^2 + (pp1.y[i]-pp2.y[j])^2)
        end
    end
    D
end
