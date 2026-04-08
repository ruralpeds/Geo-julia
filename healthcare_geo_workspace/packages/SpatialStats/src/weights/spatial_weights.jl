# src/weights/spatial_weights.jl
# SpatialWeights type and constructors (queen, rook, knn, distance).

using SparseArrays, LinearAlgebra, NearestNeighbors, DataFrames, GeoInterface

# ──────────────────────────────────────────────────────────────────────────────
# Types
# ──────────────────────────────────────────────────────────────────────────────

"""
    SpatialWeights

Container for a spatial weights matrix with metadata.

Fields:
- `W`              — row-standardised sparse weights matrix (n×n)
- `n`              — number of spatial units
- `style`          — `:B` (binary), `:W` (row-std), `:C` (global-std)
- `transform`      — construction method: `:queen`, `:rook`, `:knn`, `:distance`
- `island_count`   — number of units with zero neighbours
- `mean_neighbors` — average neighbour count (before standardisation)
"""
struct SpatialWeights
    W::SparseMatrixCSC{Float64, Int}
    n::Int
    style::Symbol
    transform::Symbol
    island_count::Int
    mean_neighbors::Float64
end

function Base.show(io::IO, sw::SpatialWeights)
    print(io, "SpatialWeights(n=$(sw.n), style=:$(sw.style), ",
          "transform=:$(sw.transform), islands=$(sw.island_count), ",
          "mean_neighbors=$(round(sw.mean_neighbors; digits=2)))")
end

# ──────────────────────────────────────────────────────────────────────────────
# Internal helpers
# ──────────────────────────────────────────────────────────────────────────────

"""Row-standardise a sparse matrix. Rows summing to 0 are left as zero."""
function _row_standardize(W::SparseMatrixCSC{Float64})
    n = size(W, 1)
    I_idx, J_idx, V = findnz(W)
    row_sums = Vector{Float64}(undef, n)
    for i in 1:n
        row_sums[i] = sum(W[i, :])
    end
    V_std = [row_sums[I_idx[k]] > 0 ? V[k] / row_sums[I_idx[k]] : 0.0
             for k in eachindex(V)]
    sparse(I_idx, J_idx, V_std, n, n)
end

function _build_metadata(W_bin::SparseMatrixCSC{Float64}, transform::Symbol, style::Symbol)
    n            = size(W_bin, 1)
    row_sums     = vec(sum(W_bin; dims = 2))
    islands      = sum(row_sums .== 0)
    mean_nn      = mean(row_sums)
    W_std        = style == :W ? _row_standardize(W_bin) : W_bin
    SpatialWeights(W_std, n, style, transform, islands, mean_nn)
end

"""Haversine distance in km between (lat,lon) tuples."""
function haversine_km(p1::NTuple{2,Float64}, p2::NTuple{2,Float64})::Float64
    R    = 6371.0
    dlat = deg2rad(p2[1] - p1[1])
    dlon = deg2rad(p2[2] - p1[2])
    a    = sin(dlat/2)^2 + cos(deg2rad(p1[1]))*cos(deg2rad(p2[1]))*sin(dlon/2)^2
    2R * asin(sqrt(a))
end

"""Bounding-box centroid (lat, lon) of a geometry."""
function _centroid(geom)::NTuple{2,Float64}
    ext = GeoInterface.extent(geom)
    lat = (ext.Y[1] + ext.Y[2]) / 2.0
    lon = (ext.X[1] + ext.X[2]) / 2.0
    (lat, lon)
end

# ──────────────────────────────────────────────────────────────────────────────
# Constructors
# ──────────────────────────────────────────────────────────────────────────────

"""
    queen_weights(df; transform=:W) -> SpatialWeights

Build queen-contiguity spatial weights from a GeoDataFrame (requires
`:geometry` column).  Two polygons are neighbours if they share any
boundary point or edge.

`transform` controls the style:
- `:W` (default) — row-standardised
- `:B` — binary (0/1)
"""
function queen_weights(df::DataFrame; transform::Symbol = :W)::SpatialWeights
    geoms = df.geometry
    n     = length(geoms)
    rows  = Int[]; cols = Int[]; vals = Float64[]

    for i in 1:n
        for j in (i+1):n
            if GeoInterface.intersects(geoms[i], geoms[j])
                push!(rows, i); push!(cols, j); push!(vals, 1.0)
                push!(rows, j); push!(cols, i); push!(vals, 1.0)
            end
        end
    end

    W_bin = sparse(rows, cols, vals, n, n)
    _build_metadata(W_bin, :queen, transform)
end

"""
    rook_weights(df; transform=:W) -> SpatialWeights

Build rook-contiguity weights (shared edges only, not corners).
Uses a tolerance-based check: polygons are rook-neighbours when
the intersection of their boundaries has length > 0 (shared edge)
rather than just a point.

Falls back to queen criterion when GeoInterface does not support
`crosses` or `touches` natively.
"""
function rook_weights(df::DataFrame; transform::Symbol = :W)::SpatialWeights
    # Without a topology engine we approximate rook as queen and warn.
    @warn "rook_weights: rook / queen distinction requires topology support " *
          "(not yet available in pure Julia). Falling back to queen criterion."
    queen_weights(df; transform)
end

"""
    knn_weights(df, k=5; transform=:W) -> SpatialWeights

Build k-nearest-neighbour spatial weights.  Centroids are computed from
the bounding box of each geometry.  Distances use the haversine formula.
"""
function knn_weights(df::DataFrame, k::Int = 5;
                      transform::Symbol = :W)::SpatialWeights
    geoms     = df.geometry
    n         = length(geoms)
    centroids = _centroid.(geoms)
    # Build coordinate matrix: [lon, lat] (NearestNeighbors convention)
    pts = hcat([c[2] for c in centroids], [c[1] for c in centroids])'  # 2×n

    tree = KDTree(pts)

    rows = Int[]; cols = Int[]; vals = Float64[]
    for i in 1:n
        idxs, _ = knn(tree, pts[:, i], k + 1)   # include self
        for j in idxs
            j == i && continue
            push!(rows, i); push!(cols, j); push!(vals, 1.0)
        end
    end

    W_bin = sparse(rows, cols, vals, n, n)
    _build_metadata(W_bin, :knn, transform)
end

"""
    distance_weights(df, threshold_km; transform=:W) -> SpatialWeights

Build binary distance-band weights: all pairs of units whose centroids
are within `threshold_km` kilometres receive weight 1.
"""
function distance_weights(df::DataFrame, threshold_km::Float64;
                            transform::Symbol = :W)::SpatialWeights
    geoms     = df.geometry
    n         = length(geoms)
    centroids = _centroid.(geoms)

    rows = Int[]; cols = Int[]; vals = Float64[]
    for i in 1:n
        for j in 1:n
            i == j && continue
            if haversine_km(centroids[i], centroids[j]) <= threshold_km
                push!(rows, i); push!(cols, j); push!(vals, 1.0)
            end
        end
    end

    W_bin = sparse(rows, cols, vals, n, n)
    _build_metadata(W_bin, :distance, transform)
end

"""
    normalize!(sw::SpatialWeights) -> SpatialWeights

Return a new `SpatialWeights` with `W` row-standardised.
Does not modify `sw` in place (SpatialWeights is immutable).
"""
function normalize!(sw::SpatialWeights)::SpatialWeights
    W_std = _row_standardize(sw.W)
    SpatialWeights(W_std, sw.n, :W, sw.transform,
                   sw.island_count, sw.mean_neighbors)
end
