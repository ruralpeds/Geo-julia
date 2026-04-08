# intensity.jl — Kernel density intensity estimation

using Statistics

"""
    kernel_intensity(pp; bandwidth=nothing, grid_n=100, kernel=:gaussian) -> NamedTuple

Kernel density estimation of spatial intensity function λ(x,y).
Evaluates on a regular grid over the window.

# Arguments
- `pp`         : PointPattern
- `bandwidth`  : kernel bandwidth h (default: Silverman's rule of thumb)
- `grid_n`     : grid resolution (grid_n × grid_n cells)
- `kernel`     : `:gaussian` or `:epanechnikov`

Returns: (grid_x, grid_y, lambda, bandwidth)
  - grid_x, grid_y : vectors of grid coordinates
  - lambda : grid_n × grid_n matrix of intensity estimates
"""
function kernel_intensity(
    pp        :: PointPattern{RectWindow};
    bandwidth :: Union{Nothing, Float64} = nothing,
    grid_n    :: Int    = 100,
    kernel    :: Symbol = :gaussian
)

    n = pp.n
    n == 0 && error("No points in pattern")

    # Silverman's rule for 2D
    h = if isnothing(bandwidth)
        σ_x = std(pp.x; corrected=false)
        σ_y = std(pp.y; corrected=false)
        σ = (σ_x + σ_y) / 2
        σ * (n * 3 / 4)^(-1/6)  # Silverman 2D
    else
        bandwidth
    end

    w = pp.window
    grid_x = range(w.xmin, w.xmax; length=grid_n)
    grid_y = range(w.ymin, w.ymax; length=grid_n)

    λ = Matrix{Float64}(undef, grid_n, grid_n)

    for (ix, gx) in enumerate(grid_x)
        for (iy, gy) in enumerate(grid_y)
            s = 0.0
            for i in 1:n
                dx = (gx - pp.x[i]) / h
                dy = (gy - pp.y[i]) / h
                r2 = dx^2 + dy^2
                if kernel == :gaussian
                    s += exp(-0.5 * r2)
                elseif kernel == :epanechnikov
                    r2 < 1.0 && (s += (1.0 - r2))
                end
            end
            λ[ix, iy] = s / (2π * h^2 * n)  # normalised Gaussian
        end
    end

    (grid_x=collect(grid_x), grid_y=collect(grid_y), lambda=λ, bandwidth=h)
end

"""
    adaptive_intensity(pp; k=10) -> NamedTuple

Adaptive kernel intensity estimation using k-nearest-neighbour bandwidth.
Each point gets its own bandwidth = distance to k-th nearest neighbour.
More accurate for heterogeneous patterns.
"""
function adaptive_intensity(
    pp :: PointPattern;
    k  :: Int = 10
)

    n = pp.n
    n <= k && error("Need more points than k=$k")

    pts  = Float64.(hcat(pp.x, pp.y)')
    tree = KDTree(pts)

    # Bandwidth at each event = distance to k-th nearest neighbour
    bandwidths = Vector{Float64}(undef, n)
    for i in 1:n
        _, d = knn(tree, pts[:, i], k+1, true)  # k+1 because self is included
        bandwidths[i] = d[end]
    end

    # Intensity at each event location (leave-one-out)
    λ_at_events = Vector{Float64}(undef, n)
    for i in 1:n
        s = 0.0
        for j in 1:n
            j == i && continue
            dx = (pp.x[i] - pp.x[j]) / bandwidths[j]
            dy = (pp.y[i] - pp.y[j]) / bandwidths[j]
            r2 = dx^2 + dy^2
            r2 < 25.0 && (s += exp(-0.5 * r2) / (2π * bandwidths[j]^2))
        end
        λ_at_events[i] = s / n
    end

    (lambda_at_events=λ_at_events, bandwidths=bandwidths)
end
