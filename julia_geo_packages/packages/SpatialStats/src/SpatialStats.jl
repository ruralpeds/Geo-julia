"""
    SpatialStats.jl

Production-quality spatial statistics package for Julia.
Implements spatial weights, autocorrelation, and spatial regression
with sparse matrices throughout. General Registry quality.

Vol 3 — Julia Package Engineering
"""
module SpatialStats

using SparseArrays
using LinearAlgebra
using Statistics
using StatsBase: StatsBase
using DataFrames
using NearestNeighbors
using Optim
using GeoInterface

# ── Type exports ────────────────────────────────────────────────────────────
export AbstractSpatialWeights, SpatialWeights
export WeightStyle, BinaryStyle, RowStandardizedStyle, GloballyStandardizedStyle
export WeightTransform, QueenTransform, RookTransform, KNNTransform, DistanceTransform
export MoranResult, LISAResult, GetisOrdResult, SpatialRegResult

# ── Weight constructor exports ───────────────────────────────────────────────
export queen_weights, rook_weights, knn_weights, distance_weights, inverse_distance_weights
export lag_spatial, normalize!

# ── Autocorrelation exports ──────────────────────────────────────────────────
export moran, moran_local, geary, getis_ord, g_local, lisa

# ── Regression exports ───────────────────────────────────────────────────────
export lm_spatial, lm_tests, slm, sem, sdm

# ── Utility exports ──────────────────────────────────────────────────────────
export haversine_km

# ============================================================================
# Weight style / transform value types (Val dispatch)
# ============================================================================

"""Abstract base for all spatial weights style tags."""
abstract type WeightStyle end

"""Binary (0/1) weights — not row-standardised."""
struct BinaryStyle <: WeightStyle end

"""Row-standardised weights — each row sums to 1."""
struct RowStandardizedStyle <: WeightStyle end

"""Globally standardised weights — sum of all weights = n."""
struct GloballyStandardizedStyle <: WeightStyle end

"""Abstract base for weight transform types."""
abstract type WeightTransform end
struct QueenTransform    <: WeightTransform end
struct RookTransform     <: WeightTransform end
struct KNNTransform      <: WeightTransform end
struct DistanceTransform <: WeightTransform end
struct InvDistTransform  <: WeightTransform end

# ============================================================================
# AbstractSpatialWeights + SpatialWeights
# ============================================================================

"""Abstract type for all spatial weight matrices."""
abstract type AbstractSpatialWeights end

"""
    SpatialWeights

Sparse row-standardised spatial weights matrix.

# Fields
- `W`              : `SparseMatrixCSC{Float64,Int}` — row-standardised adjacency
- `n`              : number of observations
- `style`          : `WeightStyle` subtype (BinaryStyle, RowStandardizedStyle, …)
- `transform`      : `WeightTransform` subtype (QueenTransform, KNNTransform, …)
- `island_count`   : observations with no neighbours
- `mean_neighbors` : mean number of non-zero neighbours per row
- `min_neighbors`  : minimum neighbours
- `max_neighbors`  : maximum neighbours
"""
struct SpatialWeights <: AbstractSpatialWeights
    W              :: SparseMatrixCSC{Float64, Int}
    n              :: Int
    style          :: WeightStyle
    transform      :: WeightTransform
    island_count   :: Int
    mean_neighbors :: Float64
    min_neighbors  :: Int
    max_neighbors  :: Int
end

function Base.show(io::IO, sw::SpatialWeights)
    tt = typeof(sw.transform) |> string
    st = typeof(sw.style)     |> string
    println(io, "SpatialWeights(n=$(sw.n), transform=$(tt), style=$(st))")
    println(io, "  mean_neighbors=$(round(sw.mean_neighbors; digits=2))")
    println(io, "  islands=$(sw.island_count)")
end

# ============================================================================
# Utility helpers
# ============================================================================

"""
    haversine_km(lat1, lon1, lat2, lon2) -> Float64

Great-circle distance in kilometres using Haversine formula.
"""
function haversine_km(lat1::Real, lon1::Real, lat2::Real, lon2::Real)::Float64
    R = 6371.0
    φ1, φ2 = deg2rad(lat1), deg2rad(lat2)
    Δφ = deg2rad(lat2 - lat1)
    Δλ = deg2rad(lon2 - lon1)
    a = sin(Δφ/2)^2 + cos(φ1)*cos(φ2)*sin(Δλ/2)^2
    2R * asin(min(1.0, sqrt(a)))
end

"""Extract (lat, lon) centroid from a GeoInterface-compatible geometry."""
function _centroid(geom)::Tuple{Float64,Float64}
    ext = GeoInterface.extent(geom)
    lat = (ext.Y[1] + ext.Y[2]) / 2.0
    lon = (ext.X[1] + ext.X[2]) / 2.0
    (lat, lon)
end

"""Build (lat, lon) centroids vector from a DataFrame with geometry column."""
function _centroids(df::DataFrame)::Vector{Tuple{Float64,Float64}}
    if :geometry ∉ propertynames(df)
        error("DataFrame must have a :geometry column")
    end
    [_centroid(g) for g in df.geometry]
end

"""Row-standardise a SparseMatrixCSC in place."""
function _row_standardize!(W::SparseMatrixCSC{Float64,Int})
    n = size(W, 1)
    row_sums = vec(sum(W; dims=2))
    rows, cols, vals = findnz(W)
    for k in eachindex(rows)
        rs = row_sums[rows[k]]
        vals[k] = rs > 0 ? vals[k] / rs : 0.0
    end
    W .= sparse(rows, cols, vals, n, n)
    W
end

function _build_metadata(W_binary::SparseMatrixCSC)
    n = size(W_binary, 1)
    row_counts = vec(sum(W_binary .!= 0; dims=2))
    island_count   = count(iszero, row_counts)
    mean_neighbors = n > 0 ? mean(row_counts) : 0.0
    min_neighbors  = n > 0 ? minimum(row_counts) : 0
    max_neighbors  = n > 0 ? maximum(row_counts) : 0
    (island_count, mean_neighbors, min_neighbors, max_neighbors)
end

# ============================================================================
# Weight constructors
# ============================================================================

include("weights/queen.jl")
include("weights/knn.jl")
include("weights/distance.jl")

# ============================================================================
# lag_spatial
# ============================================================================

"""
    lag_spatial(w::SpatialWeights, x::AbstractVector) -> Vector{Float64}

Compute the spatial lag: `Wx`.
"""
function lag_spatial(w::AbstractSpatialWeights, x::AbstractVector{<:Real})::Vector{Float64}
    w.W * Float64.(x)
end

# ============================================================================
# Autocorrelation
# ============================================================================

include("autocorrelation/morans.jl")
include("autocorrelation/lisa.jl")
include("autocorrelation/getis.jl")

# ============================================================================
# Regression
# ============================================================================

include("regression/ols_diagnostics.jl")
include("regression/spatial_lag.jl")
include("regression/spatial_error.jl")
include("regression/spatial_durbin.jl")

end # module SpatialStats
