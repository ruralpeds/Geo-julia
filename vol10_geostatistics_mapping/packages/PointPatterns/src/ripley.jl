# ripley.jl — Ripley's K(r), L(r), G(r), pair correlation function
# Uses NearestNeighbors.jl and Distances.jl for distance computation
# Monte Carlo CSR envelope tests

# ── K function ────────────────────────────────────────────────────────────────

"""
    KFunctionResult

Ripley's K function estimate with CSR envelope.
"""
struct KFunctionResult
    r       ::Vector{Float64}
    K       ::Vector{Float64}
    L       ::Vector{Float64}   # L(r) = sqrt(K(r)/π) - r (Besag transformation)
    K_csr   ::Vector{Float64}   # theoretical CSR: K(r) = πr²
    K_lo    ::Vector{Float64}   # Monte Carlo lower envelope
    K_hi    ::Vector{Float64}   # Monte Carlo upper envelope
    p_value ::Float64           # global p-value for CSR test
    area    ::Float64
end

"""
    ripley_k(pts, area; r_max, n_r, n_sim, rng, edge_correction) -> KFunctionResult

Estimate Ripley's K function with isotropic edge correction (Ripley 1976).
Uses Distances.jl for pairwise distance computation.
"""
function ripley_k(pts::AbstractMatrix, area::Real;
                  r_max::Float64=0.0,
                  n_r::Int=20,
                  n_sim::Int=99,
                  rng::AbstractRNG=Random.GLOBAL_RNG,
                  edge_correction::Bool=true)
    n  = size(pts, 1)
    A  = Float64(area)
    @assert size(pts, 2) == 2

    # Compute pairwise distances using Distances.jl
    D = Distances.pairwise(Distances.Euclidean(), pts, dims=1)

    h_max = r_max > 0 ? r_max : maximum(D) * 0.4
    r_vec = range(h_max/n_r, h_max, length=n_r) |> collect

    # Study window bounds (axis-aligned rectangle)
    x_min, x_max = extrema(pts[:,1])
    y_min, y_max = extrema(pts[:,2])
    W = (x_min, x_max, y_min, y_max)

    K_obs = _compute_k(D, pts, n, A, r_vec, W, edge_correction)
    L_obs = sqrt.(max.(K_obs ./ π, 0.0)) .- r_vec

    # Monte Carlo simulation under CSR (uniform in bounding box)
    bbox_area = (x_max - x_min) * (y_max - y_min)
    K_sims = zeros(n_sim, n_r)
    for s in 1:n_sim
        pts_sim = hcat(x_min .+ (x_max-x_min) .* rand(rng, n),
                       y_min .+ (y_max-y_min) .* rand(rng, n))
        D_sim   = Distances.pairwise(Distances.Euclidean(), pts_sim, dims=1)
        K_sims[s,:] = _compute_k(D_sim, pts_sim, n, bbox_area, r_vec, W, false)
    end

    K_lo = vec(minimum(K_sims, dims=1))
    K_hi = vec(maximum(K_sims, dims=1))

    # Global p-value: proportion of sims with max deviation ≥ observed
    obs_dev = maximum(abs.(L_obs))
    sim_dev = [maximum(abs.(sqrt.(max.(K_sims[s,:] ./ π, 0.0)) .- r_vec))
               for s in 1:n_sim]
    p_val   = mean(sim_dev .>= obs_dev)

    KFunctionResult(r_vec, K_obs, L_obs, π .* r_vec.^2, K_lo, K_hi, p_val, A)
end

function _compute_k(D, pts, n, A, r_vec, W, edge_correction)
    K = zeros(length(r_vec))
    for ri in eachindex(r_vec)
        r = r_vec[ri]
        s = 0.0
        for i in 1:n, j in 1:n
            i == j && continue
            D[i,j] > r && continue
            w = edge_correction ? _ripley_weight(pts[i,:], D[i,j], W) : 1.0
            s += (w > 0 ? 1.0 / w : 0.0)
        end
        K[ri] = A / n^2 * s
    end
    K
end

function _ripley_weight(xi, r, W)
    # Proportion of circle of radius r centred at xi inside rectangle W
    # Approximate: count angles inside [0,2π)
    n_angles = 32
    inside   = 0
    for k in 0:n_angles-1
        θ = 2π * k / n_angles
        xc = xi[1] + r * cos(θ)
        yc = xi[2] + r * sin(θ)
        if W[1] <= xc <= W[2] && W[3] <= yc <= W[4]
            inside += 1
        end
    end
    inside / n_angles
end

# ── G function (nearest-neighbour distance) ───────────────────────────────────

"""
    GFunctionResult

Nearest-neighbour distance distribution G(r).
"""
struct GFunctionResult
    r     ::Vector{Float64}
    G     ::Vector{Float64}
    G_csr ::Vector{Float64}   # CSR: G(r) = 1 - exp(-λπr²)
    G_lo  ::Vector{Float64}
    G_hi  ::Vector{Float64}
    λ     ::Float64           # estimated intensity
    p_value::Float64
end

"""
    nnd_distribution(pts, area; n_r, n_sim, rng) -> GFunctionResult

Estimate the G function (nearest-neighbour distribution) with CSR envelope.
Uses NearestNeighbors.jl for efficient nearest-neighbour distance computation.
"""
function nnd_distribution(pts::AbstractMatrix, area::Real;
                           n_r::Int=20,
                           n_sim::Int=99,
                           rng::AbstractRNG=Random.GLOBAL_RNG)
    n = size(pts, 1)
    λ = n / Float64(area)

    # Compute NNDs using NearestNeighbors.jl
    tree = NearestNeighbors.BallTree(pts')
    # k=2 because the closest is the point itself
    idxs, dists = NearestNeighbors.knn(tree, pts', 2)
    nnd = [d[2] for d in dists]  # second nearest (first is self with dist=0)

    r_max = maximum(nnd) * 0.9
    r_vec = range(0.0, r_max, length=n_r+1)[2:end] |> collect

    G_obs = [mean(nnd .<= r) for r in r_vec]
    G_csr = [1 - exp(-λ * π * r^2) for r in r_vec]

    # Monte Carlo
    x_min, x_max = extrema(pts[:,1])
    y_min, y_max = extrema(pts[:,2])
    G_sims = zeros(n_sim, n_r)
    for s in 1:n_sim
        pts_s = hcat(x_min .+ (x_max-x_min) .* rand(rng, n),
                     y_min .+ (y_max-y_min) .* rand(rng, n))
        tree_s = NearestNeighbors.BallTree(pts_s')
        idxs_s, dists_s = NearestNeighbors.knn(tree_s, pts_s', 2)
        nnd_s = [d[2] for d in dists_s]
        G_sims[s,:] = [mean(nnd_s .<= r) for r in r_vec]
    end

    G_lo = vec(minimum(G_sims, dims=1))
    G_hi = vec(maximum(G_sims, dims=1))
    obs_dev = maximum(abs.(G_obs .- G_csr))
    sim_dev = [maximum(abs.(G_sims[s,:] .- G_csr)) for s in 1:n_sim]
    p_val   = mean(sim_dev .>= obs_dev)

    GFunctionResult(r_vec, G_obs, G_csr, G_lo, G_hi, λ, p_val)
end

# ── Pair correlation function ─────────────────────────────────────────────────

"""
    pair_correlation(pts, area; r_max, n_r, bandwidth) -> NamedTuple

Pair correlation function g(r) = K'(r) / (2πr).
Uses Distances.jl for pairwise distance computation.
"""
function pair_correlation(pts::AbstractMatrix, area::Real;
                           r_max::Float64=0.0,
                           n_r::Int=20,
                           bandwidth::Float64=0.0)
    n  = size(pts, 1)
    A  = Float64(area)
    λ  = n / A
    D  = Distances.pairwise(Distances.Euclidean(), pts, dims=1)
    h_max = r_max > 0 ? r_max : maximum(D) * 0.4
    r_vec = range(h_max/n_r, h_max, length=n_r) |> collect
    bw    = bandwidth > 0 ? bandwidth : (r_vec[2] - r_vec[1]) * 2

    g = zeros(n_r)
    for ri in eachindex(r_vec)
        r = r_vec[ri]
        k = 0.0
        for i in 1:n, j in 1:n
            i == j && continue
            d = D[i,j]
            u = (d - r) / bw
            k += _gaussian_kernel(u) / bw
        end
        g[ri] = k / (n * (n-1) * 2π * r * λ^2 / A)
    end
    (r=r_vec, g=g, csr=ones(n_r))
end
