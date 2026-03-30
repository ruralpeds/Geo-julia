# generators.jl — Deterministic test-data generators for Geo-Julia packages
#
# Every generator accepts an RNG and a size parameter so tests are both
# reproducible and parameterisable. The ND (North Dakota) helpers match the
# county-level scenarios used throughout the textbook.

using Random, Statistics

# ─── 2-D coordinate generators ───────────────────────────────────────────────

"""
    gen_uniform_pts(n; rng, xlim, ylim) -> Matrix{Float64}

Generate `n` points uniformly in the rectangle [xlim[1], xlim[2]] ×
[ylim[1], ylim[2]]. Default extent matches ND's approximate lon/lat bounding
box (scaled to [0, 7.6] × [0, 3.1] for readability).
"""
function gen_uniform_pts(n::Int;
                          rng   = Random.default_rng(),
                          xlim  = (0.0, 7.6),
                          ylim  = (0.0, 3.1))
    x = xlim[1] .+ (xlim[2] - xlim[1]) .* rand(rng, n)
    y = ylim[1] .+ (ylim[2] - ylim[1]) .* rand(rng, n)
    hcat(x, y)
end

"""
    gen_clustered_pts(n; rng, n_clusters, spread) -> Matrix{Float64}

Generate `n` points drawn from `n_clusters` Gaussian clusters, each with
standard deviation `spread`. Useful for testing that facility-siting
algorithms recover the cluster structure.
"""
function gen_clustered_pts(n::Int;
                            rng       = Random.default_rng(),
                            n_clusters = 3,
                            spread    = 0.3,
                            xlim      = (0.0, 7.6),
                            ylim      = (0.0, 3.1))
    centres = gen_uniform_pts(n_clusters; rng=rng, xlim=xlim, ylim=ylim)
    pts = zeros(n, 2)
    for i in 1:n
        c = rand(rng, 1:n_clusters)
        pts[i, 1] = clamp(centres[c, 1] + spread * randn(rng), xlim[1], xlim[2])
        pts[i, 2] = clamp(centres[c, 2] + spread * randn(rng), ylim[1], ylim[2])
    end
    pts
end

"""
    gen_grid_pts(rows, cols; xlim, ylim) -> Matrix{Float64}

Generate a regular `rows × cols` grid of points. Useful for coverage and
Voronoi tests where a structured layout helps verify geometric invariants.
"""
function gen_grid_pts(rows::Int, cols::Int;
                       xlim = (0.0, 7.6),
                       ylim = (0.0, 3.1))
    xs = range(xlim[1], xlim[2]; length=cols)
    ys = range(ylim[1], ylim[2]; length=rows)
    pts = [(x, y) for y in ys for x in xs]
    hcat(first.(pts), last.(pts))
end

# ─── Weight / demand generators ───────────────────────────────────────────────

"""
    gen_weights(n; rng, lo, hi) -> Vector{Float64}

Generate `n` positive demand weights in [lo, hi]. Default range [500, 5500]
mimics ND county population variation.
"""
function gen_weights(n::Int;
                      rng = Random.default_rng(),
                      lo  = 500.0,
                      hi  = 5500.0)
    lo .+ (hi - lo) .* rand(rng, n)
end

"""
    gen_unit_weights(n) -> Vector{Float64}

Return a vector of `n` ones (unweighted scenario).
"""
gen_unit_weights(n::Int) = ones(Float64, n)

# ─── Synthetic problem instances ─────────────────────────────────────────────

"""
    gen_nd_scenario(; rng, n_demand, n_cand) -> NamedTuple

Generate a complete ND-like facility siting scenario.

Returns:
- `demand_pts`  — n_demand × 2 coordinate matrix
- `cand_pts`    — n_cand × 2 coordinate matrix
- `weights`     — population proxies for demand points
- `depot`       — 1 × 2 logistics depot (geographic centre)
"""
function gen_nd_scenario(;
                          rng      = Random.default_rng(),
                          n_demand = 20,
                          n_cand   = 15)
    demand_pts = gen_clustered_pts(n_demand; rng=rng, n_clusters=4, spread=0.5)
    cand_pts   = gen_uniform_pts(n_cand; rng=rng)
    weights    = gen_weights(n_demand; rng=rng)
    depot      = [3.8 1.55]
    (demand_pts=demand_pts, cand_pts=cand_pts, weights=weights, depot=depot)
end

"""
    gen_resource_problem(n_items; rng, value_range, weight_range) -> NamedTuple

Generate a 0/1 knapsack instance with `n_items` items.

Returns:
- `values`   — item values
- `weights`  — item weights
- `capacity` — knapsack capacity (half the total weight)
"""
function gen_resource_problem(n_items::Int;
                               rng         = Random.default_rng(),
                               value_range = (1.0, 5.0),
                               weight_range = (1.0, 4.0))
    v  = value_range[1]  .+ (value_range[2]  - value_range[1])  .* rand(rng, n_items)
    w  = weight_range[1] .+ (weight_range[2] - weight_range[1]) .* rand(rng, n_items)
    cap = sum(w) / 2.0
    (values=v, weights=w, capacity=cap)
end

"""
    gen_mdp(n_states, n_actions; rng, γ) -> NamedTuple

Generate a random MDP with `n_states` states and `n_actions` actions.
Transition matrices are row-stochastic. Returns `(R, P, γ)`.
"""
function gen_mdp(n_states::Int, n_actions::Int;
                  rng = Random.default_rng(),
                  γ   = 0.95)
    R = rand(rng, n_states, n_actions) .* 2 .- 1  # rewards in [-1, 1]
    P = zeros(n_actions, n_states, n_states)
    for a in 1:n_actions
        for s in 1:n_states
            row = rand(rng, n_states)
            P[a, s, :] = row ./ sum(row)
        end
    end
    (R=R, P=P, γ=γ)
end

"""
    gen_tsp_tour(n; rng) -> (pts, optimal_lb)

Generate `n` TSP nodes and a trivial lower bound on the tour length
(sum of nearest-neighbour distances from each point's perspective).
"""
function gen_tsp_tour(n::Int; rng = Random.default_rng())
    pts = gen_uniform_pts(n; rng=rng)
    # Lower bound: average 2 nearest-neighbour edges per point / 2
    lb  = 0.0
    for i in 1:n
        dists = [sqrt(sum((pts[i,:] .- pts[j,:]).^2)) for j in 1:n if j != i]
        lb   += minimum(dists)
    end
    (pts=pts, lb=lb/2)
end
