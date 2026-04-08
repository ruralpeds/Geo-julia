# emergency.jl — Emergency medical services: MEXCLP, dispatch, Erlang-C

# ── Input validation helpers ───────────────────────────────────────────────────
function _ems_validate_coords(m, name)
    size(m, 2) == 2 && size(m, 1) > 0 ||
        error("$(name) must be n×2 coordinate matrix (got $(size(m)))")
    all(isfinite, m) || error("$(name) contains NaN or Inf")
end

function _erlang_validate(λ, μ, c)
    λ > 0 || error("arrival rate λ must be > 0 (got $(λ))")
    μ > 0 || error("service rate μ must be > 0 (got $(μ))")
    c >= 1 || error("number of servers c must be ≥ 1 (got $(c))")
end

struct EmergencyResult
    facility_locs::Vector{Int}    # open ambulance station indices
    coverage::Vector{Float64}     # expected coverage probability per demand zone
    total_expected_coverage::Float64
    busy_fraction::Float64
    p::Int
    n_demand::Int
end

"""
    mexclp(demand_pts, cand_pts, p; weights, busy_fraction, coverage_radius) -> EmergencyResult

Maximum Expected Coverage Location Problem (Daskin 1983).
Accounts for probabilistic busy-ness of ambulances.

Expected coverage: P(covered) = 1 - q^(count of stations within radius)
where q = busy fraction (probability a unit is unavailable).
"""
function mexclp(demand_pts::AbstractMatrix,
                cand_pts::AbstractMatrix,
                p::Int;
                weights::AbstractVector=ones(size(demand_pts,1)),
                busy_fraction::Float64=0.3,
                coverage_radius::Float64=8.0,
                rng=Random.default_rng())
    _ems_validate_coords(demand_pts, "demand_pts")
    _ems_validate_coords(cand_pts,   "cand_pts")
    (busy_fraction < 0.0 || busy_fraction > 1.0) &&
        error("busy_fraction must be in [0,1] (got $(busy_fraction))")
    coverage_radius <= 0 &&
        error("coverage_radius must be > 0 (got $(coverage_radius))")
    p < 1 && error("p must be ≥ 1 (got $(p))")
    length(weights) == size(demand_pts,1) ||
        error("weights length ($(length(weights))) ≠ n_demand ($(size(demand_pts,1)))")
    any(weights .< 0) && error("all weights must be non-negative")
    n, m = size(demand_pts,1), size(cand_pts,1)
    p    = min(p, m)
    q    = busy_fraction

    # Coverage matrix: A[i,j]=1 if demand zone i covered by candidate j
    A = [sqrt(sum((demand_pts[i,:] .- cand_pts[j,:]).^2)) <= coverage_radius
         for i in 1:n, j in 1:m]

    # Expected coverage given open set: Σᵢ wᵢ·(1 - q^(count of covering stations))
    exp_cov_fn = (os) -> begin
        ec = zeros(n)
        for i in 1:n
            k = sum(A[i,j] for j in os; init=0)
            ec[i] = k == 0 ? 0.0 : 1.0 - q^k
        end
        sum(weights .* ec), ec
    end

    # Greedy with restarts
    best_set = Int[]; best_obj = -Inf

    for _ in 1:5
        open_set = Int[]
        cov_count = zeros(Int, n)  # number of covering stations per demand zone

        for _ in 1:p
            best_j = 0; best_gain = -Inf
            for j in setdiff(1:m, open_set)
                # Marginal gain of adding j
                gain = sum(weights[i] * ((1 - q^(cov_count[i]+1)) - (1 - q^cov_count[i]))
                           for i in findall(A[:,j]); init=0.0)
                if gain > best_gain; best_gain = gain; best_j = j; end
            end
            best_j == 0 && break
            push!(open_set, best_j)
            for i in findall(A[:,best_j]); cov_count[i] += 1; end
        end

        obj, _ = exp_cov_fn(open_set)
        if obj > best_obj; best_obj = obj; best_set = copy(open_set); end

        # Perturbation
        if length(open_set) > 0
            replace!(open_set, rand(rng, open_set) => rand(rng, setdiff(1:m, open_set)))
        end
    end

    best_obj, best_ec = exp_cov_fn(best_set)
    w_tot = sum(weights)
    EmergencyResult(sort(best_set), best_ec ./ max.(weights, 1e-10),
                    best_obj/w_tot, busy_fraction, p, n)
end

"""
    dispatch_assignment(incidents, stations, available) -> Vector{Int}

Assign each incident to the nearest available station.
`available[j]` = number of available vehicles at station j.
Returns assignment[i] = station index for incident i.
"""
function dispatch_assignment(incidents::AbstractMatrix,
                              stations::AbstractMatrix,
                              available::AbstractVector)
    n_inc = size(incidents,1); n_sta = size(stations,1)
    D     = [sqrt(sum((incidents[i,:] .- stations[j,:]).^2)) for i in 1:n_inc, j in 1:n_sta]
    avail = copy(Float64.(available))
    asgn  = zeros(Int, n_inc)

    for i in sortperm([minimum(D[i,:]) for i in 1:n_inc])
        best = 0; best_d = Inf
        for j in 1:n_sta
            if avail[j] > 0 && D[i,j] < best_d
                best_d = D[i,j]; best = j
            end
        end
        if best > 0
            asgn[i] = best; avail[best] -= 1.0
        else
            asgn[i] = argmin(D[i,:])  # assign anyway (busy station)
        end
    end
    asgn
end

"""
    erlang_c(λ, μ, c; t) -> NamedTuple

Erlang-C formula for M/M/c queueing system.
λ = arrival rate, μ = service rate per server, c = number of servers.
Returns P(wait), E[wait], E[queue length], and minimum c for target service level.
"""
function erlang_c(λ::Float64, μ::Float64, c::Int; target_pw::Float64=0.2)
    _erlang_validate(λ, μ, c)
    (target_pw < 0.0 || target_pw > 1.0) &&
        error("target_pw must be in [0,1] (got $(target_pw))")
    ρ = λ / (μ * c)
    ρ >= 1.0 && return (p_wait=1.0, mean_wait=Inf, mean_queue=Inf, min_servers=c+1)

    a  = λ / μ  # offered traffic

    # Erlang C: C(c,a) = (a^c/c! · c/(c-a)) / (Σ_{k=0}^{c-1} a^k/k! + a^c/c! · c/(c-a))
    # Use log-space for numerical stability
    log_terms = [k*log(a) - _lgamma_r(k+1.0) for k in 0:c-1]
    log_last  = c*log(a) - _lgamma_r(c+1.0) + log(c) - log(c - a)
    log_max   = max(maximum(log_terms), log_last)
    denom     = exp(log_max) * (sum(exp(lt - log_max) for lt in log_terms) + exp(log_last - log_max))
    num       = exp(log_last)
    p_wait    = num / denom

    mean_wait  = p_wait / (c * μ * (1 - ρ))
    mean_queue = p_wait * ρ / (1 - ρ)

    # Find minimum c for target P(wait) ≤ target_pw
    min_c = c
    for c2 in 1:50
        r2 = λ/(μ*c2)
        r2 >= 1.0 && continue
        _, pw2 = _erlang_c_core(a, c2)
        if pw2 <= target_pw; min_c = c2; break; end
    end

    (p_wait=p_wait, mean_wait=mean_wait, mean_queue=mean_queue, min_servers=min_c)
end

function _erlang_c_core(a, c)
    c - a <= 0 && return (0.0, 1.0)
    log_terms = [k*log(max(a,1e-10)) - _lgamma_r(k+1.0) for k in 0:c-1]
    log_last  = c*log(max(a,1e-10)) - _lgamma_r(c+1.0) + log(c) - log(c - a)
    log_max   = max(maximum(log_terms), log_last)
    denom     = exp(log_max)*(sum(exp(lt-log_max) for lt in log_terms)+exp(log_last-log_max))
    (a^c/_factorial_approx(c)*c/(c-a)/denom, exp(log_last)/denom)
end

_factorial_approx(n) = exp(_lgamma_r(n+1.0))

function _lgamma_r(x)
    g=7; c=[0.99999999999980993,676.5203681218851,-1259.1392167224028,
            771.32342877765313,-176.61502916214059,12.507343278686905,
            -0.13857109526572012,9.9843695780195716e-6,1.5056327351493116e-7]
    x<0.5 && return log(π/sin(π*x))-_lgamma_r(1-x)
    x-=1; aa=c[1]; t=x+g+0.5
    for i in 2:length(c); aa+=c[i]/(x+i-1); end
    0.5*log(2π)+(x+0.5)*log(t)-t+log(aa)
end
