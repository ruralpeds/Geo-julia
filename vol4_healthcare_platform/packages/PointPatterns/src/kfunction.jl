# kfunction.jl — Ripley's K-function and L-function

using DataFrames
using NearestNeighbors

"""
    Kfunction(pp; r=nothing, correction=:ripley) -> DataFrame

Estimate Ripley's K-function K(r) = E[events within r of arbitrary event] / λ.
Under CSR: K(r) = πr². K > πr² indicates clustering, K < πr² regular.

# Arguments
- `pp`         : `PointPattern{RectWindow}`
- `r`          : distances at which to evaluate K (default: 25 values up to min_side/4)
- `correction` : `:none` (raw/biased), `:ripley` (guard area, standard)

# Returns
DataFrame with: r, K, L (= √(K/π)), K_csr (= πr²), L_csr (= r)
"""
function Kfunction(
    pp::PointPattern{RectWindow};
    r::Union{Nothing, AbstractVector{<:Real}} = nothing,
    correction::Symbol = :ripley
)::DataFrame

    n = pp.n
    n < 2 && error("Need at least 2 points")

    A = area(pp.window)
    min_side = min(pp.window.xmax - pp.window.xmin,
                   pp.window.ymax - pp.window.ymin)

    r_vals = isnothing(r) ? collect(range(0.0, min_side / 4; length=25)) :
                             Float64.(r)
    n_r    = length(r_vals)

    # KDTree for efficient range queries
    pts  = Float64.(hcat(pp.x, pp.y)')   # 2 × n
    tree = KDTree(pts)

    K_vals = Vector{Float64}(undef, n_r)

    for (k, rk) in enumerate(r_vals)
        rk == 0.0 && (K_vals[k] = 0.0; continue)

        count = 0.0
        for i in 1:n
            idx = inrange(tree, pts[:, i], rk)

            if correction == :ripley
                for j in idx
                    j == i && continue
                    d_ij = sqrt((pp.x[i]-pp.x[j])^2 + (pp.y[i]-pp.y[j])^2)
                    d_ij == 0.0 && continue
                    w_ij = _ripley_weight(pp.x[i], pp.y[i], d_ij, pp.window)
                    count += 1.0 / w_ij
                end
            else
                count += Float64(length(idx) - 1)   # subtract self
            end
        end

        K_vals[k] = A / (Float64(n) * Float64(n - 1)) * count
    end

    DataFrame(
        r     = r_vals,
        K     = K_vals,
        L     = sqrt.(max.(K_vals ./ π, 0.0)),
        K_csr = π .* r_vals .^ 2,
        L_csr = r_vals
    )
end

"""
    Lfunction(pp; kwargs...) -> DataFrame

Compute L(r) = √(K(r)/π) — deviation from r indicates clustering (L > r) or regularity (L < r).
Convenience wrapper around Kfunction.
"""
Lfunction(pp; kwargs...) = Kfunction(pp; kwargs...)

# ── Ripley edge correction weight ─────────────────────────────────────────────
# Fraction of circumference of circle centered at (x,y) radius d inside window
@inline function _ripley_weight(x::Float64, y::Float64, d::Float64, w::RectWindow)::Float64
    prop = 1.0
    dx_left  = x - w.xmin
    dx_right = w.xmax - x
    dy_bot   = y - w.ymin
    dy_top   = w.ymax - y

    d > dx_left  && (prop -= acos(min(1.0, dx_left  / d)) / π)
    d > dx_right && (prop -= acos(min(1.0, dx_right / d)) / π)
    d > dy_bot   && (prop -= acos(min(1.0, dy_bot   / d)) / π)
    d > dy_top   && (prop -= acos(min(1.0, dy_top   / d)) / π)
    max(prop, 0.01)
end

"""
    envelope(pp, stat_fn; nsim=99, alpha=0.05, rng) -> DataFrame

Monte Carlo CSR envelope for K or L function.
Simulates nsim homogeneous Poisson processes and computes
pointwise simulation envelopes.

Returns DataFrame: r, K_obs, L_obs, K_lo, K_hi, L_lo, L_hi, K_csr
"""
function envelope(
    pp       :: PointPattern{RectWindow},
    stat_fn  :: Function = Kfunction;
    nsim     :: Int            = 99,
    alpha    :: Float64        = 0.05,
    rng      :: AbstractRNG    = Random.default_rng()
)::DataFrame

    λ_hat  = intensity(pp)
    obs    = stat_fn(pp)
    r_vals = obs.r
    nr     = length(r_vals)

    sim_K  = Matrix{Float64}(undef, nr, nsim)
    sim_L  = Matrix{Float64}(undef, nr, nsim)

    for k in 1:nsim
        sim_pp = simulate_csr(λ_hat, pp.window; rng)
        if sim_pp.n < 2
            sim_K[:, k] .= NaN
            sim_L[:, k] .= NaN
            continue
        end
        sim_res     = stat_fn(sim_pp; r=r_vals)
        sim_K[:, k] = sim_res.K
        sim_L[:, k] = sim_res.L
    end

    lo_q = alpha / 2
    hi_q = 1.0 - alpha / 2

    DataFrame(
        r     = r_vals,
        K_obs = obs.K,
        L_obs = obs.L,
        K_lo  = vec(mapslices(v -> quantile(filter(!isnan, v), lo_q), sim_K; dims=2)),
        K_hi  = vec(mapslices(v -> quantile(filter(!isnan, v), hi_q), sim_K; dims=2)),
        L_lo  = vec(mapslices(v -> quantile(filter(!isnan, v), lo_q), sim_L; dims=2)),
        L_hi  = vec(mapslices(v -> quantile(filter(!isnan, v), hi_q), sim_L; dims=2)),
        K_csr = π .* r_vals .^ 2,
    )
end
