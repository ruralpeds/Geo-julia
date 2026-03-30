# src/analysis/accessibility.jl
# Healthcare spatial accessibility measures: 2SFCA, E2SFCA, network-based,
# gravity model, plus the haversine distance utility.

using DataFrames, LinearAlgebra

# ──────────────────────────────────────────────────────────────────────────────
# Distance utility
# ──────────────────────────────────────────────────────────────────────────────

"""
    haversine(p1, p2) -> Float64

Compute the great-circle distance in kilometres between two geographic
coordinates given as `(lat, lon)` tuples (decimal degrees).
"""
function haversine(p1::NTuple{2, Float64}, p2::NTuple{2, Float64})::Float64
    R    = 6371.0  # mean Earth radius (km)
    dlat = deg2rad(p2[1] - p1[1])
    dlon = deg2rad(p2[2] - p1[2])
    a    = sin(dlat / 2)^2 +
           cos(deg2rad(p1[1])) * cos(deg2rad(p2[1])) * sin(dlon / 2)^2
    2R * asin(sqrt(a))
end

# ──────────────────────────────────────────────────────────────────────────────
# Two-Step Floating Catchment Area (2SFCA)
# ──────────────────────────────────────────────────────────────────────────────

"""
    two_step_fca(providers, pop_locs, catchment_km) -> DataFrame

Standard 2SFCA accessibility scores using Euclidean (haversine) distance.

**Required columns:**
- `providers` — `:lat`, `:lon`, `:supply`
- `pop_locs`  — `:lat`, `:lon`, `:population`, `:id`

Returns a `DataFrame` with columns `(:id, :accessibility)`.
"""
function two_step_fca(providers::DataFrame, pop_locs::DataFrame,
                       catchment_km::Float64)::DataFrame
    n_prov = nrow(providers)
    n_pop  = nrow(pop_locs)

    # Step 1: provider-to-population ratios
    R = Vector{Float64}(undef, n_prov)
    for j in 1:n_prov
        pj       = (providers.lat[j], providers.lon[j])
        total_pop = 0.0
        for k in 1:n_pop
            d = haversine(pj, (pop_locs.lat[k], pop_locs.lon[k]))
            d <= catchment_km && (total_pop += pop_locs.population[k])
        end
        R[j] = total_pop > 0 ? providers.supply[j] / total_pop : 0.0
    end

    # Step 2: accessibility score per population location
    A = Vector{Float64}(undef, n_pop)
    for i in 1:n_pop
        pi  = (pop_locs.lat[i], pop_locs.lon[i])
        acc = 0.0
        for j in 1:n_prov
            d = haversine(pi, (providers.lat[j], providers.lon[j]))
            d <= catchment_km && (acc += R[j])
        end
        A[i] = acc
    end

    DataFrame(id = pop_locs.id, accessibility = A)
end

# ──────────────────────────────────────────────────────────────────────────────
# Enhanced 2SFCA (E2SFCA) with distance decay
# ──────────────────────────────────────────────────────────────────────────────

"""
    e2sfca(providers, pop_locs, catchment_km;
           decay=:gaussian, sigma_km=15.0) -> DataFrame

Enhanced 2SFCA with continuous distance-decay weighting.

**Decay functions** (`:decay` keyword):
- `:gaussian`  — `exp(-0.5*(d/sigma)^2)`
- `:linear`    — `1 - d/catchment_km`
- `:inverse`   — `1 / (1 + d)`
- `:kernel`    — bisquare kernel `(1-(d/catchment_km)^2)^2`

`sigma_km` is only used by the `:gaussian` decay.
"""
function e2sfca(providers::DataFrame, pop_locs::DataFrame,
                catchment_km::Float64;
                decay::Symbol      = :gaussian,
                sigma_km::Float64  = 15.0)::DataFrame
    n_prov = nrow(providers)
    n_pop  = nrow(pop_locs)

    decay_fn = _decay_function(decay, catchment_km, sigma_km)

    # Step 1
    R = Vector{Float64}(undef, n_prov)
    for j in 1:n_prov
        pj       = (providers.lat[j], providers.lon[j])
        total_pop = 0.0
        for k in 1:n_pop
            d = haversine(pj, (pop_locs.lat[k], pop_locs.lon[k]))
            d <= catchment_km && (total_pop += decay_fn(d) * pop_locs.population[k])
        end
        R[j] = total_pop > 0 ? providers.supply[j] / total_pop : 0.0
    end

    # Step 2
    A = Vector{Float64}(undef, n_pop)
    for i in 1:n_pop
        pi  = (pop_locs.lat[i], pop_locs.lon[i])
        acc = 0.0
        for j in 1:n_prov
            d = haversine(pi, (providers.lat[j], providers.lon[j]))
            d <= catchment_km && (acc += decay_fn(d) * R[j])
        end
        A[i] = acc
    end

    DataFrame(id = pop_locs.id, accessibility = A)
end

function _decay_function(decay::Symbol, catchment_km::Float64, sigma_km::Float64)
    if decay == :gaussian
        return d -> exp(-0.5 * (d / sigma_km)^2)
    elseif decay == :linear
        return d -> max(0.0, 1.0 - d / catchment_km)
    elseif decay == :inverse
        return d -> 1.0 / (1.0 + d)
    elseif decay == :kernel   # bisquare
        return d -> d < catchment_km ? (1.0 - (d / catchment_km)^2)^2 : 0.0
    else
        error("Unknown decay function: $(decay). " *
              "Choose from :gaussian, :linear, :inverse, :kernel")
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# Network-based 2SFCA
# ──────────────────────────────────────────────────────────────────────────────

"""
    network_2sfca(providers, pop_locs, travel_time_matrix, catchment_min)
        -> DataFrame

2SFCA using a pre-computed network travel-time matrix (e.g., from OSRM).

- `travel_time_matrix` — n_pop × n_prov `Matrix{Float64}` of travel times
  in **minutes** (use `Inf` for unreachable pairs).
- `catchment_min`      — catchment threshold in minutes.
"""
function network_2sfca(providers::DataFrame, pop_locs::DataFrame,
                        travel_time_matrix::Matrix{Float64},
                        catchment_min::Float64)::DataFrame
    n_pop  = nrow(pop_locs)
    n_prov = nrow(providers)
    @assert size(travel_time_matrix) == (n_pop, n_prov) \
        "travel_time_matrix must be n_pop × n_prov"

    # Step 1: provider ratios
    R = Vector{Float64}(undef, n_prov)
    for j in 1:n_prov
        total_pop = sum(pop_locs.population[k]
                        for k in 1:n_pop
                        if travel_time_matrix[k, j] <= catchment_min;
                        init = 0.0)
        R[j] = total_pop > 0 ? providers.supply[j] / total_pop : 0.0
    end

    # Step 2: accessibility
    A = [sum(R[j] for j in 1:n_prov
             if travel_time_matrix[i, j] <= catchment_min;
             init = 0.0)
         for i in 1:n_pop]

    DataFrame(id = pop_locs.id, accessibility = A)
end

# ──────────────────────────────────────────────────────────────────────────────
# Gravity-model accessibility
# ──────────────────────────────────────────────────────────────────────────────

"""
    gravity_accessibility(providers, pop_locs; beta=2.0) -> DataFrame

Gravity-model accessibility index:

    A_i = Σ_j  S_j / d(i,j)^beta

where `S_j` is provider supply and `d(i,j)` is haversine distance (km).
Self-pairs (distance = 0) are skipped.
"""
function gravity_accessibility(providers::DataFrame, pop_locs::DataFrame;
                                 beta::Float64 = 2.0)::DataFrame
    n_prov = nrow(providers)
    n_pop  = nrow(pop_locs)

    A = Vector{Float64}(undef, n_pop)
    for i in 1:n_pop
        pi  = (pop_locs.lat[i], pop_locs.lon[i])
        acc = 0.0
        for j in 1:n_prov
            d = haversine(pi, (providers.lat[j], providers.lon[j]))
            d > 0 && (acc += providers.supply[j] / d^beta)
        end
        A[i] = acc
    end

    DataFrame(id = pop_locs.id, accessibility = A)
end
