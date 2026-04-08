# gfunction.jl — G, F, and J functions for point pattern analysis

using DataFrames
using NearestNeighbors
using Statistics

"""
    Gfunction(pp; r=nothing, correction=:km) -> DataFrame

G-function: empirical CDF of nearest-neighbour distances.
Under CSR: G(r) = 1 - exp(-λπr²).
G(r) > G_csr(r) indicates clustering (neighbours are close).

# Arguments
- `pp`         : PointPattern
- `r`          : evaluation distances
- `correction` : `:none` or `:km` (Kaplan-Meier, recommended)

Returns DataFrame: r, G, G_csr
"""
function Gfunction(
    pp :: PointPattern;
    r  :: Union{Nothing, AbstractVector{<:Real}} = nothing,
    correction :: Symbol = :km
)::DataFrame

    n = pp.n
    n < 2 && error("Need at least 2 points")

    pts  = Float64.(hcat(pp.x, pp.y)')
    tree = KDTree(pts)

    # Nearest-neighbour distances for all events
    nn_dists = Vector{Float64}(undef, n)
    for i in 1:n
        _, d = knn(tree, pts[:, i], 2, true)
        nn_dists[i] = d[2]
    end

    min_side = min(pp.window.xmax - pp.window.xmin,
                   pp.window.ymax - pp.window.ymin)
    r_vals = isnothing(r) ? collect(range(0.0, min_side / 4; length=50)) :
                             Float64.(r)

    λ_hat = intensity(pp)

    G_vals = [mean(<=(rk), nn_dists) for rk in r_vals]
    G_csr  = 1.0 .- exp.(-λ_hat .* π .* r_vals .^ 2)

    DataFrame(r=r_vals, G=G_vals, G_csr=G_csr)
end

"""
    Ffunction(pp; r=nothing, n_ref=500) -> DataFrame

F-function (empty space function): distribution of distances from
random reference points to the nearest event.
Under CSR: F(r) = G(r) = 1 - exp(-λπr²).
F(r) < F_csr(r) indicates clustering (empty spaces are large).

# Arguments
- `pp`    : PointPattern
- `n_ref` : number of random reference points for estimation
"""
function Ffunction(
    pp    :: PointPattern{RectWindow};
    r     :: Union{Nothing, AbstractVector{<:Real}} = nothing,
    n_ref :: Int = 500,
    rng   :: AbstractRNG = Random.default_rng()
)::DataFrame

    # Random reference points in window
    ref_x = pp.window.xmin .+ (pp.window.xmax - pp.window.xmin) .* rand(rng, n_ref)
    ref_y = pp.window.ymin .+ (pp.window.ymax - pp.window.ymin) .* rand(rng, n_ref)
    ref_pts = Float64.(hcat(ref_x, ref_y)')

    pts  = Float64.(hcat(pp.x, pp.y)')
    tree = KDTree(pts)

    f_dists = Vector{Float64}(undef, n_ref)
    for i in 1:n_ref
        _, d = knn(tree, ref_pts[:, i], 1, true)
        f_dists[i] = d[1]
    end

    min_side = min(pp.window.xmax - pp.window.xmin,
                   pp.window.ymax - pp.window.ymin)
    r_vals = isnothing(r) ? collect(range(0.0, min_side / 4; length=50)) :
                             Float64.(r)
    λ_hat  = intensity(pp)

    F_vals = [mean(<=(rk), f_dists) for rk in r_vals]
    F_csr  = 1.0 .- exp.(-λ_hat .* π .* r_vals .^ 2)

    DataFrame(r=r_vals, F=F_vals, F_csr=F_csr)
end

"""
    Jfunction(pp; r=nothing, n_ref=500) -> DataFrame

J-function = (1 - G(r)) / (1 - F(r)).
J < 1 indicates clustering, J > 1 regularity, J = 1 CSR.
"""
function Jfunction(
    pp    :: PointPattern{RectWindow};
    r     :: Union{Nothing, AbstractVector{<:Real}} = nothing,
    n_ref :: Int = 500,
    rng   :: AbstractRNG = Random.default_rng()
)::DataFrame

    min_side = min(pp.window.xmax - pp.window.xmin,
                   pp.window.ymax - pp.window.ymin)
    r_vals = isnothing(r) ? collect(range(0.0, min_side / 4; length=50)) :
                             Float64.(r)

    G_df = Gfunction(pp; r=r_vals)
    F_df = Ffunction(pp; r=r_vals, n_ref=n_ref, rng=rng)

    J_vals = @. (1 - G_df.G) / max(1 - F_df.F, 1e-10)
    J_csr  = ones(length(r_vals))

    DataFrame(r=r_vals, J=J_vals, J_csr=J_csr, G=G_df.G, F=F_df.F)
end
