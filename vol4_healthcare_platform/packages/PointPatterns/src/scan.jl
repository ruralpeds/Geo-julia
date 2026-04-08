# scan.jl — Kulldorff spatial scan statistic (1997)

using Distributions
using NearestNeighbors
using Statistics

"""
    scan_statistic(cases, population, coords;
                   max_pop_fraction=0.5, n_centers=100, nsim=999) -> NamedTuple

Kulldorff (1997) spatial scan statistic for disease cluster detection.
Finds the most likely spatial cluster using a circular scan window.

# Algorithm
1. For each of n_centers candidate zone centers (defined by the data locations),
   grow a circle to include populations up to max_pop_fraction of total.
2. Compute Poisson log-likelihood ratio (LLR) for each candidate zone.
3. The maximum LLR defines the most likely cluster.
4. Monte Carlo p-value: simulate nsim null datasets (cases ∝ population),
   compute max LLR for each; p = fraction with max_LLR_sim ≥ max_LLR_obs.

# Arguments
- `cases`            : observed case counts per area (Vector{Int})
- `population`       : at-risk population per area (Vector{Float64})
- `coords`           : n×2 matrix of [lat lon] or [x y] centroids
- `max_pop_fraction` : maximum fraction of total population in scan window
- `n_centers`        : number of candidate zone centers (default: all n areas)
- `nsim`             : Monte Carlo simulations for p-value

# Returns
NamedTuple: (most_likely_cluster, llr, p_value, included_areas, secondary_clusters)
"""
function scan_statistic(
    cases            :: AbstractVector{<:Integer},
    population       :: AbstractVector{<:Real},
    coords           :: AbstractMatrix{<:Real};
    max_pop_fraction :: Float64 = 0.5,
    n_centers        :: Int     = length(cases),
    nsim             :: Int     = 999,
    rng              :: AbstractRNG = Random.default_rng()
)

    n       = length(cases)
    n == length(population) == size(coords, 1) ||
        error("cases, population, and coords must all have length n")

    C_total = Float64(sum(cases))
    P_total = Float64(sum(population))
    max_pop = max_pop_fraction * P_total

    # ── Build candidate zones ──────────────────────────────────────────────
    zones = _build_candidate_zones(coords, population, max_pop, n_centers)

    # ── Compute observed max LLR ──────────────────────────────────────────
    llr_obs_result = _max_llr(cases, population, zones, C_total, P_total)

    # ── Monte Carlo p-value ────────────────────────────────────────────────
    expected = population .* (C_total / P_total)
    llr_sim  = Vector{Float64}(undef, nsim)

    for k in 1:nsim
        sim_cases  = rand.(rng, Poisson.(expected))
        C_sim      = Float64(sum(sim_cases))
        llr_sim[k] = _max_llr(sim_cases, population, zones, C_sim, P_total).max_llr
    end

    p_val = mean(llr_sim .>= llr_obs_result.max_llr)

    # ── Secondary clusters ─────────────────────────────────────────────────
    # Find top clusters that do not overlap with the most likely cluster
    primary_areas = Set(llr_obs_result.best_zone_areas)
    secondary = []
    for (zi, zone_areas) in enumerate(zones)
        zi == llr_obs_result.best_zone && continue
        isempty(intersect(primary_areas, Set(zone_areas))) || continue
        c_z = Float64(sum(cases[zone_areas]))
        p_z = sum(population[zone_areas])
        E_z = p_z * C_total / P_total
        llr = _poisson_llr(c_z, C_total, E_z)
        llr > 0 && push!(secondary, (llr=llr, areas=zone_areas))
        length(secondary) >= 3 && break
    end

    (
        most_likely_cluster = llr_obs_result.best_zone,
        llr                 = llr_obs_result.max_llr,
        p_value             = p_val,
        included_areas      = llr_obs_result.best_zone_areas,
        secondary_clusters  = secondary,
        relative_risk       = llr_obs_result.max_llr > 0 ?
            (sum(cases[llr_obs_result.best_zone_areas]) /
             max(sum(population[llr_obs_result.best_zone_areas]) * C_total / P_total, 1e-9)) : 1.0,
    )
end

# ── Build candidate zones ───────────────────────────────────────────────────

function _build_candidate_zones(
    coords     :: AbstractMatrix{<:Real},
    population :: AbstractVector{<:Real},
    max_pop    :: Float64,
    n_centers  :: Int
)::Vector{Vector{Int}}

    n = size(coords, 1)
    # Use top n_centers areas by population as zone centers
    center_idx = partialsortperm(population, 1:min(n_centers, n); rev=true)

    pts  = Float64.(coords')  # 2 × n
    tree = KDTree(pts)

    zones = Vector{Vector{Int}}()
    for ci in center_idx
        # Sort all areas by distance from center ci
        idxs, _ = knn(tree, pts[:, ci], n, true)
        zone_areas = Int[]
        cum_pop = 0.0
        for j in idxs
            cum_pop += population[j]
            cum_pop > max_pop && break
            push!(zone_areas, j)
            length(zone_areas) >= 2 && push!(zones, copy(zone_areas))
        end
    end

    unique(zones)
end

# ── Poisson log-likelihood ratio ─────────────────────────────────────────────

function _poisson_llr(c::Float64, C::Float64, E::Float64)::Float64
    (E <= 0 || C - E <= 0) && return 0.0
    c / E <= (C - c) / max(C - E, 1e-15) && return 0.0  # not excess risk
    llr = 0.0
    c > 0       && (llr += c * log(c / E))
    (C - c) > 0 && (llr += (C - c) * log((C - c) / max(C - E, 1e-15)))
    llr
end

function _max_llr(
    cases      :: AbstractVector,
    population :: AbstractVector{<:Real},
    zones      :: Vector{Vector{Int}},
    C_total    :: Float64,
    P_total    :: Float64
)

    max_llr    = -Inf
    best_zone  = -1
    best_areas = Int[]

    for (zi, zone_areas) in enumerate(zones)
        isempty(zone_areas) && continue
        c_z = Float64(sum(cases[zone_areas]))
        p_z = sum(population[zone_areas])
        E_z = p_z * C_total / P_total
        llr = _poisson_llr(c_z, C_total, E_z)
        if llr > max_llr
            max_llr    = llr
            best_zone  = zi
            best_areas = zone_areas
        end
    end

    (max_llr=max_llr, best_zone=best_zone, best_zone_areas=best_areas)
end
