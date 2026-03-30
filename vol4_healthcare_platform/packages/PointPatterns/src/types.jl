# types.jl — Core types for PointPatterns.jl

"""Abstract supertype for observation windows."""
abstract type ObservationWindow end

"""
    RectWindow(xmin, xmax, ymin, ymax)

Rectangular observation window defined by bounding coordinates.
"""
struct RectWindow <: ObservationWindow
    xmin :: Float64
    xmax :: Float64
    ymin :: Float64
    ymax :: Float64

    function RectWindow(xmin::Real, xmax::Real, ymin::Real, ymax::Real)
        xmin < xmax || error("xmin must be < xmax")
        ymin < ymax || error("ymin must be < ymax")
        new(Float64(xmin), Float64(xmax), Float64(ymin), Float64(ymax))
    end
end

"""
    PolyWindow(coords)

Polygon observation window defined by a vector of (x,y) tuples.
"""
struct PolyWindow <: ObservationWindow
    coords :: Vector{Tuple{Float64, Float64}}
    xmin   :: Float64
    xmax   :: Float64
    ymin   :: Float64
    ymax   :: Float64

    function PolyWindow(coords::Vector{<:Tuple})
        xs = [c[1] for c in coords]
        ys = [c[2] for c in coords]
        new([(Float64(c[1]), Float64(c[2])) for c in coords],
            minimum(xs), maximum(xs), minimum(ys), maximum(ys))
    end
end

"""Compute area of an ObservationWindow."""
area(w::RectWindow)  = (w.xmax - w.xmin) * (w.ymax - w.ymin)
area(w::PolyWindow)  = _shoelace_area(w.coords)
perimeter(w::RectWindow) = 2 * ((w.xmax - w.xmin) + (w.ymax - w.ymin))

"""Shoelace formula for polygon area."""
function _shoelace_area(coords::Vector{Tuple{Float64,Float64}})
    n = length(coords)
    s = 0.0
    for i in 1:n
        j = mod1(i+1, n)
        s += coords[i][1] * coords[j][2] - coords[j][1] * coords[i][2]
    end
    abs(s) / 2.0
end

"""Check if point (x,y) is inside the window."""
@inline function inside(pt::Tuple{Float64,Float64}, w::RectWindow)
    w.xmin <= pt[1] <= w.xmax && w.ymin <= pt[2] <= w.ymax
end

function inside(pt::Tuple{Float64,Float64}, w::PolyWindow)
    # Ray casting algorithm for point-in-polygon
    x, y  = pt
    n     = length(w.coords)
    inside = false
    j = n
    for i in 1:n
        xi, yi = w.coords[i]
        xj, yj = w.coords[j]
        if ((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)
            inside = !inside
        end
        j = i
    end
    inside
end

"""
    PointPattern(x, y, window; marks=nothing)

A spatial point pattern: observed event locations within a study window.

# Arguments
- `x, y`   : event coordinates (same units as window)
- `window` : `RectWindow` or `PolyWindow` defining the study area
- `marks`  : optional `DataFrame` of mark variables (e.g. case type, severity)
"""
struct PointPattern{W <: ObservationWindow}
    x      :: Vector{Float64}
    y      :: Vector{Float64}
    marks  :: Union{Nothing, DataFrame}
    window :: W
    n      :: Int

    function PointPattern(x::AbstractVector, y::AbstractVector, window::W;
                           marks = nothing) where W <: ObservationWindow
        length(x) == length(y) ||
            throw(DimensionMismatch("x and y must have equal length"))
        new{W}(Float64.(x), Float64.(y), marks, window, length(x))
    end
end

function Base.show(io::IO, pp::PointPattern)
    println(io, "PointPattern(n=$(pp.n))")
    println(io, "  window: $(typeof(pp.window))(area=$(round(area(pp.window); digits=2)))")
    println(io, "  intensity: $(round(intensity(pp); digits=6)) events/unit²")
end

"""Observed intensity: events per unit area."""
intensity(pp::PointPattern) = pp.n / area(pp.window)

"""
    simulate_csr(λ, window; rng) -> PointPattern

Simulate a homogeneous Poisson process (Complete Spatial Randomness)
with intensity λ. Used for Monte Carlo CSR envelope testing.
"""
function simulate_csr(λ::Real, window::RectWindow;
                       rng::AbstractRNG = Random.default_rng())::PointPattern
    A = area(window)
    n = rand(rng, Poisson(λ * A))
    x = window.xmin .+ (window.xmax - window.xmin) .* rand(rng, n)
    y = window.ymin .+ (window.ymax - window.ymin) .* rand(rng, n)
    PointPattern(x, y, window)
end

function simulate_csr(λ::Real, window::PolyWindow;
                       rng::AbstractRNG = Random.default_rng())::PointPattern
    A = area(window)
    n_expected = rand(rng, Poisson(λ * A))
    xs = Float64[]; ys = Float64[]
    attempts = 0
    while length(xs) < n_expected && attempts < n_expected * 20
        px = window.xmin + rand(rng) * (window.xmax - window.xmin)
        py = window.ymin + rand(rng) * (window.ymax - window.ymin)
        if inside((px, py), window)
            push!(xs, px); push!(ys, py)
        end
        attempts += 1
    end
    PointPattern(xs, ys, window)
end
