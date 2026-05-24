# smoothing.jl — Empirical Bayes smoothing, spatial scan statistic
# Uses Distributions.jl for Poisson random variates

# ── Empirical Bayes smoothing (Marshall 1991) ─────────────────────────────────

"""
    EBSmoothedResult

Empirical Bayes (EB) smoothed rates.

The Gamma-Poisson EB model:
  O_i ~ Poisson(E_i · θ_i)
  θ_i ~ Gamma(α, β)

EB estimates: α̂, β̂ via moment matching. Posterior mean:
  θ̂_i = (O_i + α̂) / (E_i + β̂)
"""
struct EBSmoothedResult
    θ_hat    ::Vector{Float64}   # EB smoothed rates
    smr_raw  ::Vector{Float64}   # raw SMR = O/E
    α_hat    ::Float64           # Gamma shape
    β_hat    ::Float64           # Gamma rate
    shrinkage::Vector{Float64}   # how much pulled toward mean
end

"""
    eb_smooth(O, E) -> EBSmoothedResult

Empirical Bayes smoothing of area-level counts using Gamma-Poisson model.
"""
function eb_smooth(O::AbstractVector, E::AbstractVector)
    n  = length(O)
    O_f = Float64.(O); E_f = Float64.(E)

    θ_raw = O_f ./ max.(E_f, 1e-10)
    μ_hat = sum(O_f) / sum(E_f)

    # Moment-based variance of θ
    E_bar = mean(E_f)
    var_θ = var(θ_raw) - μ_hat / E_bar
    var_θ = max(var_θ, 1e-10)

    α_hat = μ_hat^2 / var_θ
    β_hat = μ_hat   / var_θ

    # Posterior mean: E[θ_i | O_i] = (O_i + α̂) / (E_i + β̂)
    θ_hat = (O_f .+ α_hat) ./ (E_f .+ β_hat)

    # Shrinkage: how much each estimate moved toward global mean
    shrink = 1.0 .- (θ_hat .- μ_hat) ./ max.(θ_raw .- μ_hat, 1e-10)
    shrink = clamp.(shrink, 0.0, 1.0)

    EBSmoothedResult(θ_hat, θ_raw, α_hat, β_hat, shrink)
end

# ── Kernel spatial smoother ───────────────────────────────────────────────────

"""
    kernel_smooth_rates(O, E, coords; bandwidth, kernel) -> Vector{Float64}

Kernel smoothing of rates: for each area, compute weighted average rate
using distance-based kernel weights.
"""
function kernel_smooth_rates(O::AbstractVector, E::AbstractVector,
                              coords::AbstractMatrix;
                              bandwidth::Float64=0.0,
                              kernel::Symbol=:gaussian)
    n    = length(O)
    O_f  = Float64.(O); E_f = Float64.(E)
    bw   = bandwidth > 0 ? bandwidth :
           begin
               dists = [sqrt(sum((coords[i,:] .- coords[j,:]).^2))
                        for i in 1:n, j in 1:n]
               median(sort(dists[:]; rev=false)[n+1:2n])  # median non-zero dist
           end

    θ_smooth = zeros(n)
    for i in 1:n
        weights = zeros(n)
        for j in 1:n
            d = sqrt(sum((coords[i,:] .- coords[j,:]).^2))
            weights[j] = if kernel == :gaussian
                exp(-d^2 / (2 * bw^2))
            elseif kernel == :bisquare
                d < bw ? (1 - (d/bw)^2)^2 : 0.0
            else  # uniform
                d <= bw ? 1.0 : 0.0
            end
        end
        w_sum = dot(weights, E_f)
        θ_smooth[i] = w_sum > 0 ? dot(weights, O_f) / w_sum : sum(O_f)/sum(E_f)
    end
    θ_smooth
end

# ── Spatial scan statistic (Kulldorff 1997) ───────────────────────────────────

"""
    ScanResult

Circular spatial scan cluster result.
"""
struct ScanResult
    centre_idx  ::Int
    radius      ::Float64
    n_inside    ::Int
    O_inside    ::Float64
    E_inside    ::Float64
    O_outside   ::Float64
    E_outside   ::Float64
    llr         ::Float64   # log-likelihood ratio
    p_value     ::Float64   # Monte Carlo p-value
    significant ::Bool
end

"""
    spatial_scan(O, E, coords; max_pop_frac, n_sim, alpha, rng) -> Vector{ScanResult}

Circular Poisson spatial scan statistic (Kulldorff 1997).
Uses Distributions.jl for Poisson random variate generation.
"""
function spatial_scan(O::AbstractVector, E::AbstractVector,
                       coords::AbstractMatrix;
                       max_pop_frac::Float64=0.5,
                       n_sim::Int=99,
                       alpha::Float64=0.05,
                       rng::AbstractRNG=Random.GLOBAL_RNG)
    n     = length(O)
    O_tot = sum(O); E_tot = sum(E)
    O_f   = Float64.(O); E_f = Float64.(E)

    # Precompute all pairwise distances
    D = [sqrt(sum((coords[i,:] .- coords[j,:]).^2)) for i in 1:n, j in 1:n]

    # Candidate windows: for each centre, increasing radii
    best_llr = -Inf; best_result = nothing

    for ctr in 1:n
        sorted_idx = sortperm(D[ctr,:])
        O_in = 0.0; E_in = 0.0

        for k in 1:n
            j = sorted_idx[k]
            O_in += O_f[j]; E_in += E_f[j]
            E_in > max_pop_frac * E_tot && break
            O_out = O_tot - O_in; E_out = max(E_tot - E_in, 1e-10)

            # Poisson LLR
            llr = if O_in / max(E_in, 1e-10) > O_tot / max(E_tot, 1e-10)
                _poisson_llr(O_in, E_in, O_out, E_out, O_tot, E_tot)
            else 0.0 end

            if llr > best_llr
                best_llr = llr
                best_result = (ctr=ctr, radius=D[ctr,j], n_in=k,
                                O_in=O_in, E_in=E_in,
                                O_out=O_out, E_out=E_out, llr=llr)
            end
        end
    end

    isnothing(best_result) && return ScanResult[]

    # Monte Carlo p-value using Distributions.jl Poisson
    mc_llrs = zeros(n_sim)
    for s in 1:n_sim
        O_mc = [rand_poisson(rng, E_f[i]) for i in 1:n]
        mc_llrs[s] = _best_scan_llr(Float64.(O_mc), E_f, D, max_pop_frac, O_tot, E_tot)
    end
    p_val = mean(mc_llrs .>= best_llr)

    [ScanResult(best_result.ctr, best_result.radius, best_result.n_in,
                best_result.O_in, best_result.E_in,
                best_result.O_out, best_result.E_out,
                best_llr, p_val, p_val < alpha)]
end

function _poisson_llr(O_in, E_in, O_out, E_out, O_tot, E_tot)
    eps = 1e-10
    t1 = O_in  > 0 ? O_in  * log(O_in  / max(E_in,  eps)) : 0.0
    t2 = O_out > 0 ? O_out * log(O_out / max(E_out, eps)) : 0.0
    t3 = O_tot > 0 ? O_tot * log(O_tot / max(E_tot, eps)) : 0.0
    t1 + t2 - t3
end

function _best_scan_llr(O, E, D, max_pop_frac, O_tot_ref, E_tot)
    n = length(O)
    O_tot = sum(O); best = 0.0
    for ctr in 1:n
        idx = sortperm(D[ctr,:])
        O_in = 0.0; E_in = 0.0
        for k in 1:n
            j = idx[k]
            O_in += O[j]; E_in += E[j]
            E_in > max_pop_frac * E_tot && break
            O_out = O_tot - O_in; E_out = max(E_tot - E_in, 1e-10)
            llr = O_in/max(E_in,1e-10) > O_tot/max(E_tot,1e-10) ?
                  _poisson_llr(O_in, E_in, O_out, E_out, O_tot, E_tot) : 0.0
            llr > best && (best = llr)
        end
    end
    best
end

"""
    rand_poisson(rng, λ) -> Int

Draw from Poisson(λ) using Distributions.jl.
"""
function rand_poisson(rng::AbstractRNG, λ::Float64)
    λ <= 0 && return 0
    dist = Distributions.Poisson(λ)
    rand(rng, dist)
end
