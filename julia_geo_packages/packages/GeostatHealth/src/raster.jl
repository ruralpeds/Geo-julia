# raster.jl — Raster integration: grid helpers, zonal statistics, uncertainty

using Statistics, Random

# ── Regular grid creation ─────────────────────────────────────────────────────

"""
    RasterGrid

A regular 2-D grid of prediction locations.

Fields: x (column coords), y (row coords), coords (n_cells×2 matrix),
nx, ny.
"""
struct RasterGrid
    x     ::Vector{Float64}
    y     ::Vector{Float64}
    coords::Matrix{Float64}   # (nx*ny) × 2, row-major (x varies fastest)
    nx    ::Int
    ny    ::Int
end

"""
    create_grid(x_range, y_range) -> RasterGrid

Build a regular raster grid from 1-D x and y coordinate vectors (or ranges).

```julia
g = create_grid(0.0:1.0:10.0, 0.0:1.0:8.0)
```
"""
function create_grid(x_range, y_range)
    xv = collect(Float64, x_range)
    yv = collect(Float64, y_range)
    nx = length(xv); ny = length(yv)
    coords = Matrix{Float64}(undef, nx * ny, 2)
    k = 0
    for yi in yv, xi in xv
        k += 1
        coords[k, 1] = xi
        coords[k, 2] = yi
    end
    RasterGrid(xv, yv, coords, nx, ny)
end

# ── Zonal statistics ──────────────────────────────────────────────────────────

"""
    BoundingBox

Axis-aligned bounding box (simple polygon proxy for zonal masking).
"""
struct BoundingBox
    xmin::Float64
    xmax::Float64
    ymin::Float64
    ymax::Float64
end

"""
    points_in_bbox(coords, bbox) -> Vector{Int}

Return the row indices of `coords` (n×2) that fall inside `bbox`.
"""
function points_in_bbox(coords::AbstractMatrix, bbox::BoundingBox)
    findall(i -> bbox.xmin <= coords[i,1] <= bbox.xmax &&
                 bbox.ymin <= coords[i,2] <= bbox.ymax,
            1:size(coords, 1))
end

"""
    zonal_statistics(z, coords, bbox) -> NamedTuple

Compute summary statistics for observations `z` at `coords` inside `bbox`.

Returns (n, mean, std, min, max, sum) or `nothing` if no points fall inside.
"""
function zonal_statistics(z::AbstractVector, coords::AbstractMatrix,
                           bbox::BoundingBox)
    idx = points_in_bbox(coords, bbox)
    isempty(idx) && return nothing
    zz = z[idx]
    (n=length(zz), mean=mean(zz), std=std(zz),
     min=minimum(zz), max=maximum(zz), sum=sum(zz))
end

# ── Kriging uncertainty surface ────────────────────────────────────────────────

"""
    UncertaintySurface

Kriging-based prediction and uncertainty on a regular raster grid.

Fields: grid, z_hat (mean), sigma2 (kriging variance), lower_95, upper_95
(all reshaped as ny×nx matrices).
"""
struct UncertaintySurface
    grid    ::RasterGrid
    z_hat   ::Matrix{Float64}
    sigma2  ::Matrix{Float64}
    lower_95::Matrix{Float64}
    upper_95::Matrix{Float64}
end

"""
    uncertainty_surface(ok, grid; max_neighbors) -> UncertaintySurface

Build a kriging prediction + 95 % prediction interval on every cell of
`grid` using local ordinary kriging (`max_neighbors` nearest data points).

The surface encodes spatial uncertainty for visualisation and downstream
decision support.
"""
function uncertainty_surface(ok::OrdinaryKrigingResult,
                              grid::RasterGrid;
                              max_neighbors::Int=32)
    n_cells = grid.nx * grid.ny

    ẑ_vec, σ²_vec = ok_predict_local(ok, grid.coords; max_neighbors=max_neighbors)

    z_mat    = reshape(ẑ_vec,  grid.ny, grid.nx)
    s2_mat   = reshape(σ²_vec, grid.ny, grid.nx)
    lo_mat   = z_mat .- 1.96 .* sqrt.(s2_mat)
    hi_mat   = z_mat .+ 1.96 .* sqrt.(s2_mat)

    UncertaintySurface(grid, z_mat, s2_mat, lo_mat, hi_mat)
end

# ── Synthetic raster-style data sources ───────────────────────────────────────

"""
    synthetic_worldpop_grid(bbox; resolution, seed) -> NamedTuple

Generate a synthetic WorldPop-style population density raster covering
`bbox` at the given spatial `resolution`.

Returns (grid, density) where `density` is a vector of simulated
population values at each grid cell centroid.  Intended for unit testing
and offline development when real WorldPop tiles are unavailable.
"""
function synthetic_worldpop_grid(bbox::BoundingBox;
                                  resolution::Float64=1.0,
                                  seed::Int=42)
    rng = MersenneTwister(seed)
    g   = create_grid(bbox.xmin:resolution:bbox.xmax,
                      bbox.ymin:resolution:bbox.ymax)
    # Smooth log-normal surface (crude population model)
    n_cells = size(g.coords, 1)
    noise   = randn(rng, n_cells)
    density = [exp(sin(g.coords[k,1]/5) + cos(g.coords[k,2]/5) + 0.3 * noise[k])
               for k in 1:n_cells]
    (grid=g, density=density)
end

"""
    synthetic_ghsl_grid(bbox; resolution, seed) -> NamedTuple

Generate a synthetic GHSL (Global Human Settlement Layer) built-up area
fraction raster.  Values are in [0, 1].
"""
function synthetic_ghsl_grid(bbox::BoundingBox;
                               resolution::Float64=1.0,
                               seed::Int=99)
    rng = MersenneTwister(seed)
    g   = create_grid(bbox.xmin:resolution:bbox.xmax,
                      bbox.ymin:resolution:bbox.ymax)
    built_up = clamp.(0.5 .+
                      0.4 .* [sin(g.coords[k,1]/3) * cos(g.coords[k,2]/3)
                               for k in 1:size(g.coords, 1)] .+
                      0.1 .* randn(rng, size(g.coords, 1)), 0.0, 1.0)
    (grid=g, built_up=built_up)
end
