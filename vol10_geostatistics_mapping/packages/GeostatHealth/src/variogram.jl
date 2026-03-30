# variogram.jl — Empirical variogram and theoretical model fitting

using Statistics, LinearAlgebra

# ── Empirical variogram ───────────────────────────────────────────────────────

"""
    EmpiricalVariogram

Empirical (sample) variogram.

Fields: lags (bin centres), gamma (semi-variance), n_pairs, bandwidth.
"""
struct EmpiricalVariogram
    lags     ::Vector{Float64}
    gamma    ::Vector{Float64}   # semi-variance estimate
    n_pairs  ::Vector{Int}
    bandwidth::Float64
    estimator::Symbol   # :classical or :robust
end

"""
    empirical_variogram(coords, z; n_lags, lag_max, bandwidth, estimator) -> EmpiricalVariogram

Compute the empirical variogram from observations z at locations coords (n×2).

- `:classical` : γ̂(h) = (1/2|N(h)|) Σ_{N(h)} (z_i - z_j)²  (Matheron 1963)
- `:robust`    : γ̂(h) = (1/2)(mean |z_i-z_j|^{0.5})⁴ / (0.457+0.494/|N(h)|)
                          (Cressie-Hawkins 1980)
"""
function empirical_variogram(coords::AbstractMatrix, z::AbstractVector;
                              n_lags::Int=12,
                              lag_max::Real=0.0,
                              bandwidth::Real=0.0,
                              estimator::Symbol=:classical)
    n = length(z)
    @assert size(coords, 1) == n && size(coords, 2) == 2

    # All pairwise distances and squared differences
    pairs_h  = Float64[]
    pairs_sq = Float64[]
    for i in 1:n-1, j in i+1:n
        d = sqrt(sum((coords[i,:] .- coords[j,:]).^2))
        push!(pairs_h,  d)
        push!(pairs_sq, (z[i] - z[j])^2)
    end

    # Determine lag max and bandwidth
    h_max = lag_max > 0 ? Float64(lag_max) : maximum(pairs_h) * 0.5
    bw    = bandwidth > 0 ? Float64(bandwidth) : h_max / n_lags

    # Bin pairs into lag classes
    lag_centres = [(k - 0.5) * bw for k in 1:n_lags]
    gamma_v  = Float64[]
    n_pairs  = Int[]

    for k in 1:n_lags
        lo = (k - 1) * bw; hi = k * bw
        mask = (pairs_h .>= lo) .& (pairs_h .< hi)
        m    = sum(mask)
        if m == 0
            push!(gamma_v, NaN); push!(n_pairs, 0); continue
        end
        sq_k = pairs_sq[mask]
        if estimator == :classical
            γ = mean(sq_k) / 2.0
        else  # robust Cressie-Hawkins
            root4 = mean(sqrt.(sqrt.(abs.(sq_k))))^4
            γ     = root4 / (2 * (0.457 + 0.494/m))
        end
        push!(gamma_v, γ); push!(n_pairs, m)
    end

    EmpiricalVariogram(lag_centres, gamma_v, n_pairs, bw, estimator)
end

# ── Theoretical variogram models ─────────────────────────────────────────────

"""
    VariogramModel

Theoretical variogram model: γ(h) = nugget + (sill-nugget)·f(h/range).
"""
struct VariogramModel
    model ::Symbol   # :spherical, :exponential, :gaussian, :matern
    nugget::Float64
    sill  ::Float64   # partial sill = sill - nugget
    range ::Float64
    kappa ::Float64   # Matérn smoothness (ignored for others)
end

"""
    variogram_value(vm, h) -> Float64

Evaluate the variogram model at lag distance `h`.
"""
function variogram_value(vm::VariogramModel, h::Real)
    h <= 0 && return 0.0
    r = vm.range; c0 = vm.nugget; c = vm.sill - vm.nugget
    c < 0 && (c = 0.0)
    if vm.model == :spherical
        if h >= r; return c0 + c
        else
            u = h/r
            return c0 + c * (1.5u - 0.5u^3)
        end
    elseif vm.model == :exponential
        return c0 + c * (1 - exp(-3h/r))
    elseif vm.model == :gaussian
        return c0 + c * (1 - exp(-3h^2/r^2))
    elseif vm.model == :matern
        ν = vm.kappa
        if h == 0; return c0; end
        u = sqrt(2ν) * h / r
        # Matérn: c0 + c*(1 - 2^{1-ν}/Γ(ν) * u^ν * K_ν(u))
        # Approximate with series for ν=0.5 (exponential) and ν=1.5, 2.5
        if abs(ν - 0.5) < 0.01
            return c0 + c * (1 - exp(-u))
        elseif abs(ν - 1.5) < 0.01
            return c0 + c * (1 - (1 + u)*exp(-u))
        elseif abs(ν - 2.5) < 0.01
            return c0 + c * (1 - (1 + u + u^2/3)*exp(-u))
        else
            # Fall back to exponential
            return c0 + c * (1 - exp(-3h/r))
        end
    end
    error("Unknown model: $(vm.model)")
end

"""
    covariance_value(vm, h) -> Float64

Covariance C(h) = C(0) - γ(h), where C(0) = sill.
"""
covariance_value(vm::VariogramModel, h::Real) = vm.sill - variogram_value(vm, h)

# ── WLS variogram fitting ─────────────────────────────────────────────────────

"""
    fit_variogram(ev; model, nugget_init, sill_init, range_init,
                  kappa, max_iter, tol) -> VariogramModel

Fit a theoretical variogram model to an empirical variogram by
weighted least squares (WLS):

  min Σ_k N(h_k) · [γ̂(h_k) / γ_model(h_k) - 1]²

(Cressie 1985 — downweights bins with few pairs).
"""
function fit_variogram(ev::EmpiricalVariogram;
                       model::Symbol=:spherical,
                       nugget_init::Float64=0.0,
                       sill_init::Float64=0.0,
                       range_init::Float64=0.0,
                       kappa::Float64=1.5,
                       max_iter::Int=200,
                       tol::Float64=1e-7)
    # Filter valid bins
    mask  = .!isnan.(ev.gamma) .& (ev.n_pairs .> 0)
    h_obs = ev.lags[mask]
    γ_obs = ev.gamma[mask]
    n_obs = Float64.(ev.n_pairs[mask])
    isempty(h_obs) && error("No valid variogram bins")

    # Initialise
    c0 = nugget_init >= 0 ? nugget_init : 0.0
    c  = sill_init  >  0 ? sill_init   : maximum(γ_obs)
    r  = range_init >  0 ? range_init  :
         h_obs[findfirst(γ_obs .>= 0.7 * maximum(γ_obs))]

    θ = [c0, c, r]  # nugget, sill, range

    wls_fn = function(θ)
        c0v = max(θ[1], 0.0); cv = max(θ[2], c0v + 1e-10); rv = max(θ[3], 1e-10)
        vm_t = VariogramModel(model, c0v, cv, rv, kappa)
        s = 0.0
        for k in eachindex(h_obs)
            γm = variogram_value(vm_t, h_obs[k])
            γm > 0 || continue
            s += n_obs[k] * (γ_obs[k]/γm - 1.0)^2
        end
        s
    end

    # Nelder-Mead simplex (3 params)
    θ = _nelder_mead(wls_fn, θ; max_iter=max_iter, tol=tol)

    c0_f = max(θ[1], 0.0)
    c_f  = max(θ[2], c0_f + 1e-10)
    r_f  = max(θ[3], 1e-10)

    VariogramModel(model, c0_f, c_f, r_f, kappa)
end

# ── Nelder-Mead simplex optimizer ─────────────────────────────────────────────

function _nelder_mead(f, x0; max_iter=200, tol=1e-7,
                      α=1.0, γ_nm=2.0, ρ=0.5, σ=0.5)
    n = length(x0)
    # Build initial simplex
    simplex = [copy(x0) for _ in 1:n+1]
    for i in 1:n
        simplex[i+1][i] += max(abs(x0[i]) * 0.1, 0.01)
    end
    vals = [f(s) for s in simplex]

    for _ in 1:max_iter
        ord     = sortperm(vals)
        simplex = simplex[ord]; vals = vals[ord]
        # Centroid (excluding worst)
        xbar = mean(simplex[1:end-1])
        # Reflect
        xr   = xbar .+ α .* (xbar .- simplex[end])
        fr   = f(xr)
        if fr < vals[1]
            xe = xbar .+ γ_nm .* (xr .- xbar)
            fe = f(xe)
            if fe < fr; simplex[end] = xe; vals[end] = fe
            else; simplex[end] = xr; vals[end] = fr; end
        elseif fr < vals[end-1]
            simplex[end] = xr; vals[end] = fr
        else
            xc = xbar .+ ρ .* (simplex[end] .- xbar)
            fc = f(xc)
            if fc < vals[end]; simplex[end] = xc; vals[end] = fc
            else
                for i in 2:n+1
                    simplex[i] = simplex[1] .+ σ .* (simplex[i] .- simplex[1])
                    vals[i] = f(simplex[i])
                end
            end
        end
        if maximum(abs.(vals .- vals[1])) < tol; break; end
    end
    simplex[argmin(vals)]
end

"""
    variogram_summary(vm) -> NamedTuple

Print-friendly summary of a variogram model.
"""
function variogram_summary(vm::VariogramModel)
    (model=vm.model, nugget=vm.nugget, sill=vm.sill, range=vm.range,
     nugget_ratio=vm.nugget/max(vm.sill, 1e-10))
end
