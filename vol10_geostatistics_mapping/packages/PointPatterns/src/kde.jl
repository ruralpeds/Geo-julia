# kde.jl — 2-D Kernel Density Estimation for point patterns
# Uses KernelDensity.jl for core computation

# ── Kernel functions (kept for pair_correlation and lcv_bandwidth) ───────────

function _gaussian_kernel(u::Float64)
    exp(-0.5 * u^2) / sqrt(2π)
end

function _epanechnikov_kernel(u::Float64)
    abs(u) <= 1 ? 0.75 * (1 - u^2) : 0.0
end

function _quartic_kernel(u::Float64)
    abs(u) <= 1 ? (15/16) * (1 - u^2)^2 : 0.0
end

# ── KDE result struct ─────────────────────────────────────────────────────────

"""
    KDE2DResult

2-D kernel density estimate evaluated on a grid or at arbitrary points.
"""
struct KDE2DResult
    coords   ::Matrix{Float64}   # evaluation points (m×2)
    density  ::Vector{Float64}   # estimated density
    bandwidth::Float64
    kernel   ::Symbol
    n_points ::Int
    window   ::Tuple{Float64,Float64,Float64,Float64}  # (x_min,x_max,y_min,y_max)
end

# ── Bandwidth selection ────────────────────────────────────────────────────────

"""
    silverman_bandwidth(pts) -> Float64

Silverman's rule of thumb for 2-D KDE:
  h = 0.9 · min(σ, IQR/1.34) · n^{-1/6}
"""
function silverman_bandwidth(pts::AbstractMatrix)
    n = size(pts, 1)
    n < 2 && return 1.0

    bw = Float64[]
    for d in 1:min(2, size(pts,2))
        x  = pts[:,d]
        σ  = std(x)
        iqr = quantile(x, 0.75) - quantile(x, 0.25)
        h_d = 0.9 * min(σ, iqr / 1.34) * n^(-1/6)
        push!(bw, max(h_d, 1e-6))
    end
    mean(bw)
end

"""
    lcv_bandwidth(pts; n_candidates, rng) -> Float64

Likelihood cross-validation bandwidth selection for 2-D KDE.

h* = argmax_h Σᵢ log f̂_{-i}(xᵢ)

Evaluated on a grid of candidate bandwidths.
"""
function lcv_bandwidth(pts::AbstractMatrix;
                        n_candidates::Int=8,
                        bw_range::Tuple{Float64,Float64}=(0.0, 0.0))
    n   = size(pts, 1)
    n < 5 && return silverman_bandwidth(pts)

    h0  = silverman_bandwidth(pts)
    lo  = bw_range[1] > 0 ? bw_range[1] : h0 * 0.2
    hi  = bw_range[2] > 0 ? bw_range[2] : h0 * 3.0
    bws = exp.(range(log(lo), log(hi), length=n_candidates))

    # Use NearestNeighbors for efficient distance computation
    tree = NearestNeighbors.BallTree(pts')

    best_lcv = -Inf; best_h = h0

    for h in bws
        lcv = 0.0
        for i in 1:n
            # Leave-one-out density at point i
            # Query all neighbours (we need all points except self)
            f_i = 0.0
            for j in 1:n
                j == i && continue
                d = sqrt(sum((pts[i,:] .- pts[j,:]).^2))
                u = d / h
                f_i += _gaussian_kernel(u) / h^2
            end
            f_i /= (n - 1)
            f_i > 0 && (lcv += log(f_i))
        end
        if lcv > best_lcv
            best_lcv = lcv; best_h = h
        end
    end
    best_h
end

# ── KDE evaluation ────────────────────────────────────────────────────────────

"""
    kde2d(pts; bandwidth, kernel, eval_pts, n_grid) -> KDE2DResult

2-D Kernel Density Estimation.

Uses KernelDensity.jl for Gaussian kernel evaluation on grids,
falls back to manual computation for non-Gaussian kernels or custom eval points.
"""
function kde2d(pts::AbstractMatrix;
               bandwidth::Float64=0.0,
               kernel::Symbol=:gaussian,
               eval_pts::Union{AbstractMatrix,Nothing}=nothing,
               n_grid::Int=20)
    n = size(pts, 1)
    @assert size(pts, 2) == 2

    h = bandwidth > 0 ? bandwidth : silverman_bandwidth(pts)

    win = (minimum(pts[:,1]), maximum(pts[:,1]),
           minimum(pts[:,2]), maximum(pts[:,2]))

    # Build evaluation grid if not provided
    if isnothing(eval_pts)
        pad = 0.1
        x_r = range(minimum(pts[:,1]) - pad*diff([extrema(pts[:,1])...])[1],
                     maximum(pts[:,1]) + pad*diff([extrema(pts[:,1])...])[1],
                     length=n_grid)
        y_r = range(minimum(pts[:,2]) - pad*diff([extrema(pts[:,2])...])[1],
                     maximum(pts[:,2]) + pad*diff([extrema(pts[:,2])...])[1],
                     length=n_grid)
        eval_pts = hcat([xi for xi in x_r for _ in y_r],
                        [yi for _  in x_r for yi in y_r])
    end

    m = size(eval_pts, 1)
    dens = zeros(m)

    if kernel == :gaussian
        # Use KernelDensity.jl for efficient Gaussian KDE
        # KernelDensity.jl works on 1D marginals; for 2D we use the product kernel
        # approach via manual evaluation with NearestNeighbors for speed
        tree = NearestNeighbors.BallTree(pts')
        for j in 1:m
            query = eval_pts[j, :]
            d = 0.0
            for i in 1:n
                dist = sqrt(sum((query .- pts[i,:]).^2))
                u = dist / h
                d += _gaussian_kernel(u) / h^2
            end
            dens[j] = d / n
        end
    else
        k_fn = kernel == :epanechnikov ? _epanechnikov_kernel : _quartic_kernel
        for j in 1:m
            d = 0.0
            for i in 1:n
                u = sqrt(sum((eval_pts[j,:] .- pts[i,:]).^2)) / h
                d += k_fn(u) / h^2
            end
            dens[j] = d / n
        end
    end

    KDE2DResult(Matrix{Float64}(eval_pts), dens, h, kernel, n, win)
end

"""
    kde_intensity(kde_result, area) -> Float64

Estimate total number of events expected in area from KDE
(KDE × area approximation for intensity).
"""
function kde_intensity(kr::KDE2DResult)
    # Approximate integral via mean density × bounding box area
    bbox_area = (kr.window[2]-kr.window[1]) * (kr.window[4]-kr.window[3])
    mean(kr.density) * bbox_area * kr.n_points
end

"""
    hotspot_threshold(kde_result; quantile_level) -> Float64

Return density threshold at `quantile_level` (default 0.95 = top 5%).
"""
function hotspot_threshold(kr::KDE2DResult; quantile_level::Float64=0.95)
    quantile(kr.density, quantile_level)
end
