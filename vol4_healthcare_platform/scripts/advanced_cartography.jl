#!/usr/bin/env julia
# scripts/advanced_cartography.jl
#
# Advanced cartographic methods for healthcare GIS:
#   - Bivariate choropleth maps (Steven's bivariate scheme)
#   - Dot density maps for population distribution
#   - Dorling cartogram (force-directed circle packing)
#   - GeoStats.jl kriging for spatial interpolation
#
# Prerequisites: GeoMakie, CairoMakie, GeoInterface, GeoStats, GeoTables
# Vol 4 — Advanced Methods, Real Data, and Deployment, Chapters 28 & 32

using Statistics
using LinearAlgebra
using Random

# ── Bivariate Choropleth Map ──────────────────────────────────────────────────

# Joshua Stevens 3×3 bivariate palette
const BIVARIATE_PALETTE_3x3 = [
    "#e8e8e8"  "#ace4e4"  "#5ac8c8";   # Low var1  × Low/Mid/High var2
    "#dfb0d6"  "#a5add3"  "#5698b9";   # Mid var1
    "#be64ac"  "#8c62aa"  "#3b4994"    # High var1
]

# Extended 4×4 palette (more granular)
const BIVARIATE_PALETTE_4x4 = [
    "#f3f3f3"  "#b8d6e0"  "#5ca8c8"  "#0073b6";
    "#e8c2d9"  "#b0aec8"  "#5a8ab5"  "#0061a0";
    "#d596bf"  "#a082ab"  "#506b9e"  "#00508a";
    "#c066a0"  "#8e5592"  "#3f4e87"  "#003f74"
]

"""
    quantile_classify(v, k) -> Vector{Int}

Classify vector v into k quantile classes (1..k).
"""
function quantile_classify(v::AbstractVector{<:Real}, k::Int)::Vector{Int}
    q = quantile(v, range(0, 1; length=k+1))
    [min(searchsortedfirst(q, vi), k) for vi in v]
end

"""
    bivariate_map(geoms, var1, var2; title1, title2, outfile, k, projection)

Create a bivariate choropleth map encoding two variables simultaneously.
Requires GeoMakie and CairoMakie.

# Color encoding (3×3):
- Low-Low   (row 1, col 1) = light grey
- High-High (row 3, col 3) = dark purple
- High var1 only = purple; High var2 only = blue-teal

# Arguments
- `geoms`    : vector of GeoInterface-compatible geometries
- `var1`     : first variable values (x-axis of bivariate legend)
- `var2`     : second variable values (y-axis of bivariate legend)
- `k`        : grid size (3 = 3×3, 4 = 4×4)
"""
function bivariate_map(
    geoms,
    var1 :: Vector{Float64},
    var2 :: Vector{Float64};
    title1     :: String = "Variable 1",
    title2     :: String = "Variable 2",
    outfile    :: String = "bivariate_map.pdf",
    k          :: Int    = 3,
    projection :: String = "+proj=laea +lat_0=45 +lon_0=-96"
)
    palette = k == 3 ? BIVARIATE_PALETTE_3x3 : BIVARIATE_PALETTE_4x4

    c1 = quantile_classify(var1, k)
    c2 = quantile_classify(var2, k)

    # Lazy-load visualization dependencies
    GeoMakie_m  = Base.require(Base.PkgId(Base.UUID("db073c08-6b98-4ee5-b6a4-5efafaea5259"), "GeoMakie"))
    CairoMakie_m = Base.require(Base.PkgId(Base.UUID("13f3f980-e62b-5c42-98c6-ff1f3baf88f0"), "CairoMakie"))

    fig = CairoMakie_m.Figure(resolution=(1400, 900))
    ax  = GeoMakie_m.GeoAxis(fig[1, 1];
          dest  = projection,
          title = "Bivariate: $(title1) × $(title2)",
          titlefont = :bold)

    colors = [CairoMakie_m.parse(CairoMakie_m.RGBf, palette[c1[i], c2[i]]) for i in eachindex(geoms)]
    CairoMakie_m.poly!(ax, geoms; color=colors, strokecolor=:white, strokewidth=0.3)

    # Bivariate legend inset
    ax_leg = CairoMakie_m.Axis(fig[1, 2];
        width=100, height=100,
        xlabel=title1, ylabel=title2,
        xlabelsize=11, ylabelsize=11, aspect=1)

    for r in 1:k, c in 1:k
        CairoMakie_m.poly!(ax_leg,
            CairoMakie_m.Rect((r-1)/k, (c-1)/k, 1/k, 1/k);
            color=CairoMakie_m.parse(CairoMakie_m.RGBf, palette[r,c]),
            strokecolor=:white, strokewidth=0.5)
    end
    CairoMakie_m.hidedecorations!(ax_leg; label=false)

    CairoMakie_m.save(outfile, fig; pt_per_unit=1)
    @info "Bivariate map saved to $(outfile)"
    fig
end

# ── Dot Density Map ───────────────────────────────────────────────────────────

"""
    dot_density_positions(geoms, populations; dots_per_person=1000, rng) -> (xs, ys)

Generate random dot positions for a dot density map.
Each dot represents `dots_per_person` people, randomly placed within each polygon.

Uses rejection sampling (bounding box → point-in-polygon check).
Returns (all_x, all_y) coordinate vectors.
"""
function dot_density_positions(
    geoms,
    populations :: AbstractVector{<:Real};
    dots_per_person :: Int          = 1000,
    rng             :: AbstractRNG  = MersenneTwister(42),
    max_attempts_multiplier :: Int  = 20
)

    all_x = Float64[]
    all_y = Float64[]

    for (geom, pop) in zip(geoms, populations)
        n_dots = max(1, round(Int, pop / dots_per_person))

        # Bounding box
        ext  = GeoInterface.extent(geom)
        xmin, xmax = ext.X
        ymin, ymax = ext.Y
        range_x = xmax - xmin
        range_y = ymax - ymin

        placed   = 0
        attempts = 0
        max_att  = n_dots * max_attempts_multiplier

        while placed < n_dots && attempts < max_att
            px = xmin + rand(rng) * range_x
            py = ymin + rand(rng) * range_y
            if GeoInterface.contains(geom, GeoInterface.Point([px, py]))
                push!(all_x, px)
                push!(all_y, py)
                placed += 1
            end
            attempts += 1
        end
        placed < n_dots && @warn "Only placed $(placed)/$(n_dots) dots for a geometry ($(attempts) attempts)"
    end

    (all_x, all_y)
end

"""
    dot_density_map(geoms, populations; dots_per_person, outfile, ...)

Draw a dot density map and save to file.
"""
function dot_density_map(
    geoms,
    populations     :: AbstractVector{<:Real};
    dots_per_person :: Int    = 1000,
    rng             :: AbstractRNG = MersenneTwister(42),
    projection      :: String = "+proj=laea +lat_0=45 +lon_0=-96",
    dot_color                 = :navy,
    dot_size        :: Float64 = 1.5,
    outfile         :: String  = "dot_density.pdf"
)
    xs, ys = dot_density_positions(geoms, populations; dots_per_person, rng)

    CairoMakie_m = Base.require(Base.PkgId(Base.UUID("13f3f980-e62b-5c42-98c6-ff1f3baf88f0"), "CairoMakie"))
    GeoMakie_m   = Base.require(Base.PkgId(Base.UUID("db073c08-6b98-4ee5-b6a4-5efafaea5259"), "GeoMakie"))

    fig = CairoMakie_m.Figure(resolution=(1400, 900))
    ax  = GeoMakie_m.GeoAxis(fig[1,1];
          dest  = projection,
          title = "Population Dot Density (1 dot = $(dots_per_person) people)")

    CairoMakie_m.poly!(ax, geoms; color=:white, strokecolor=:grey60, strokewidth=0.3)
    CairoMakie_m.scatter!(ax, xs, ys; color=dot_color, markersize=dot_size, alpha=0.6)

    CairoMakie_m.save(outfile, fig; pt_per_unit=1)
    @info "$(length(xs)) dots placed → $(outfile)"
    fig
end

# ── Dorling Cartogram ─────────────────────────────────────────────────────────

"""
    dorling_cartogram(centroids, values, geoms; iterations=100, friction=0.25) -> NamedTuple

Compute Dorling cartogram positions using iterative force-directed layout.
Circle areas are proportional to `values` (e.g. county population).

# Algorithm
1. Initialize circles at county centroids with radii ∝ √(value)
2. Iteratively resolve overlaps with repulsion forces
3. Attraction toward original centroid prevents excessive drift

# Returns
(positions, radii) — updated centroid matrix and circle radius vector
"""
function dorling_cartogram(
    centroids  :: Matrix{Float64},    # n×2 [x y]
    values     :: Vector{Float64},
    geoms      = nothing;
    iterations :: Int     = 100,
    friction   :: Float64 = 0.25,
    max_radius :: Union{Nothing, Float64} = nothing
)

    n = size(centroids, 1)
    n == length(values) || error("centroids and values must have same length")

    # Scale: radius ∝ √(value), calibrated so largest circle has reasonable size
    range_val = maximum(centroids; dims=1) .- minimum(centroids; dims=1)
    mean_extent = mean(range_val)

    scale = if !isnothing(max_radius)
        max_radius / sqrt(maximum(values))
    else
        0.4 * mean_extent / sqrt(maximum(values))
    end

    radii = scale .* sqrt.(values)
    pos   = copy(centroids)
    vel   = zeros(n, 2)

    for _ in 1:iterations
        forces = zeros(n, 2)

        for i in 1:n
            for j in (i+1):n
                dx   = pos[i,1] - pos[j,1]
                dy   = pos[i,2] - pos[j,2]
                dist = sqrt(dx^2 + dy^2)
                r_sum = radii[i] + radii[j]

                if dist < r_sum && dist > 1e-10
                    # Repulsion proportional to overlap
                    overlap = r_sum - dist
                    mag = overlap / dist
                    forces[i,1] += mag * dx;  forces[i,2] += mag * dy
                    forces[j,1] -= mag * dx;  forces[j,2] -= mag * dy
                end
            end
            # Attraction toward original centroid (gravity)
            forces[i,1] += friction * (centroids[i,1] - pos[i,1])
            forces[i,2] += friction * (centroids[i,2] - pos[i,2])
        end

        vel  .= 0.5 .* vel .+ forces
        pos  .+= 0.1 .* vel
    end

    (positions=pos, radii=radii)
end

# ── GeoStats.jl Kriging Extension ────────────────────────────────────────────

"""
    fit_healthcare_variogram(df, var; max_lag=200.0, nlags=30) -> variogram model

Fit empirical variogram and select the best theoretical model
(Spherical, Exponential, Gaussian) by Weighted Least Squares.
Requires GeoStats.jl and GeoTables.jl.
"""
function fit_healthcare_variogram(
    df      :: Any,         # DataFrame with :geom_col geometry column
    var     :: Symbol;
    max_lag :: Float64 = 200.0,   # km
    nlags   :: Int     = 30,
    geom_col :: Symbol = :geometry
)
    GeoStats_m  = Base.require(Base.PkgId(Base.UUID("dcc97b0b-8ce5-5539-9008-bb190f959ef6"), "GeoStats"))
    GeoTables_m = Base.require(Base.PkgId(Base.UUID("e502b557-6362-48c1-8219-d316d3952e35"), "GeoTables"))

    gt = GeoTables_m.GeoTable(df; geometry=geom_col)

    γ_emp = GeoStats_m.EmpiricalVariogram(gt, var;
        nlags  = nlags,
        maxlag = max_lag * 1000)   # km → m

    models = [GeoStats_m.SphericalVariogram,
              GeoStats_m.ExponentialVariogram,
              GeoStats_m.GaussianVariogram]

    fitted = [GeoStats_m.fit(M, γ_emp) for M in models]
    wls_errors = [sum((γ_emp.ordinate .- fitted[k](γ_emp.abscissa)).^2 ./
                      max.(γ_emp.counts, 1))
                  for k in eachindex(models)]

    best_idx = argmin(wls_errors)
    @info "Best variogram: $(models[best_idx]) (WLS=$(round(wls_errors[best_idx]; digits=4)))"
    fitted[best_idx]
end

"""
    kriging_surface(df, var, target_grid; variogram=nothing, geom_col=:geometry)

Ordinary kriging interpolation of a healthcare variable to a target grid.
Requires GeoStats.jl.
"""
function kriging_surface(
    df          :: Any,
    var         :: Symbol,
    target_grid;
    variogram   = nothing,
    geom_col    :: Symbol = :geometry
)
    GeoStats_m  = Base.require(Base.PkgId(Base.UUID("dcc97b0b-8ce5-5539-9008-bb190f959ef6"), "GeoStats"))
    GeoTables_m = Base.require(Base.PkgId(Base.UUID("e502b557-6362-48c1-8219-d316d3952e35"), "GeoTables"))

    gt = GeoTables_m.GeoTable(df; geometry=geom_col)
    γ  = isnothing(variogram) ? fit_healthcare_variogram(df, var) : variogram

    problem  = GeoStats_m.EstimationProblem(gt, target_grid, var)
    solver   = GeoStats_m.Kriging(var => (variogram=γ,))
    GeoStats_m.solve(problem, solver)
end

# ── GeoDataFrames st_difference contribution ─────────────────────────────────

"""
    st_difference(gdf_a, gdf_b)

Compute geometric difference: geometry A minus intersection with geometry B.
Contribution to GeoDataFrames.jl (Chapter 32.1).
Requires ArchGDAL.jl.
"""
function st_difference(gdf_a, gdf_b)
    ArchGDAL_m = Base.require(Base.PkgId(Base.UUID("c9ce4bd3-c3d5-55b8-8973-c0e20141b8c3"), "ArchGDAL"))
    GeoInterface_m = Base.require(Base.PkgId(Base.UUID("cf35fbd7-0cd7-5166-be24-54bfbe79505f"), "GeoInterface"))

    # Dissolve gdf_b into a single geometry
    b_geoms   = [GeoInterface_m.convert(ArchGDAL_m.IGeometry, g) for g in gdf_b.geometry]
    b_union   = foldl((a, b) -> ArchGDAL_m.union(a, b), b_geoms)

    result_geoms = map(gdf_a.geometry) do geom_a
        a = GeoInterface_m.convert(ArchGDAL_m.IGeometry, geom_a)
        ArchGDAL_m.difference(a, b_union)
    end

    result = copy(gdf_a)
    result.geometry = result_geoms
    result
end
