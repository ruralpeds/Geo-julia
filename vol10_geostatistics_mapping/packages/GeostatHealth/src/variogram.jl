# variogram.jl — Empirical variogram and theoretical model fitting
# Backed by GeoStats.jl / Variography.jl

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

Uses GeoStats.jl EmpiricalVariogram internally.

- `:classical` : Matheron (1963) estimator
- `:robust`    : Cressie-Hawkins (1980) estimator
"""
function empirical_variogram(coords::AbstractMatrix, z::AbstractVector;
                              n_lags::Int=12,
                              lag_max::Real=0.0,
                              bandwidth::Real=0.0,
                              estimator::Symbol=:classical)
    n = length(z)
    @assert size(coords, 1) == n && size(coords, 2) == 2

    # Build a georeferenced table for GeoStats
    points = [Meshes.Point(coords[i,1], coords[i,2]) for i in 1:n]
    domain = Meshes.PointSet(points)
    table  = (; Z = Float64.(z))
    geotable = GeoTables.georef(table, domain)

    # Determine lag max from data if not provided
    h_max = if lag_max > 0
        Float64(lag_max)
    else
        # Compute max pairwise distance / 2
        max_d = 0.0
        for i in 1:n-1, j in i+1:n
            d = sqrt((coords[i,1]-coords[j,1])^2 + (coords[i,2]-coords[j,2])^2)
            d > max_d && (max_d = d)
        end
        max_d * 0.5
    end

    bw = bandwidth > 0 ? Float64(bandwidth) : h_max / n_lags

    # Use GeoStats EmpiricalVariogram
    # Check for CressieHawkinsEstimator availability (API varies across versions)
    ev = if estimator == :robust && isdefined(Variography, :CressieHawkinsEstimator)
        Variography.EmpiricalVariogram(geotable, :Z;
            nlags=n_lags, maxlag=h_max,
            estimator=Variography.CressieHawkinsEstimator())
    else
        Variography.EmpiricalVariogram(geotable, :Z;
            nlags=n_lags, maxlag=h_max)
    end

    # Extract values from GeoStats empirical variogram
    lags_out  = Float64[]
    gamma_out = Float64[]
    npairs_out = Int[]

    for (h, γ, np) in Variography.values(ev)
        push!(lags_out, h)
        push!(gamma_out, np > 0 ? γ : NaN)
        push!(npairs_out, round(Int, np))
    end

    EmpiricalVariogram(lags_out, gamma_out, npairs_out, bw, estimator)
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
    _to_geostats_variogram(vm::VariogramModel)

Convert our VariogramModel to a GeoStats variogram object.
"""
function _to_geostats_variogram(vm::VariogramModel)
    c = max(vm.sill - vm.nugget, 0.0)
    r = vm.range
    n = vm.nugget
    base = if vm.model == :spherical
        Variography.SphericalVariogram(sill=c, range=r)
    elseif vm.model == :exponential
        Variography.ExponentialVariogram(sill=c, range=r)
    elseif vm.model == :gaussian
        Variography.GaussianVariogram(sill=c, range=r)
    elseif vm.model == :matern
        Variography.MaternVariogram(sill=c, range=r, order=vm.kappa)
    else
        error("Unknown model: $(vm.model)")
    end
    if n > 0
        Variography.NuggetEffect(nugget=n) + base
    else
        base
    end
end

"""
    variogram_value(vm, h) -> Float64

Evaluate the variogram model at lag distance `h`.
"""
function variogram_value(vm::VariogramModel, h::Real)
    h <= 0 && return 0.0
    gv = _to_geostats_variogram(vm)
    # Evaluate the GeoStats variogram at distance h
    # GeoStats variograms are callable with Point arguments
    p1 = Meshes.Point(0.0, 0.0)
    p2 = Meshes.Point(Float64(h), 0.0)
    Float64(gv(p1, p2))
end

"""
    covariance_value(vm, h) -> Float64

Covariance C(h) = C(0) - γ(h), where C(0) = sill.
"""
covariance_value(vm::VariogramModel, h::Real) = vm.sill - variogram_value(vm, h)

# ── Variogram fitting via GeoStats ───────────────────────────────────────────

"""
    _geostats_model_type(model::Symbol)

Return the GeoStats variogram model type for fitting.
"""
function _geostats_model_type(model::Symbol)
    if model == :spherical
        Variography.SphericalVariogram
    elseif model == :exponential
        Variography.ExponentialVariogram
    elseif model == :gaussian
        Variography.GaussianVariogram
    elseif model == :matern
        Variography.MaternVariogram
    else
        error("Unknown model: $model")
    end
end

"""
    fit_variogram(ev; model, nugget_init, sill_init, range_init,
                  kappa, max_iter, tol) -> VariogramModel

Fit a theoretical variogram model to an empirical variogram using
GeoStats.jl fitting routines.
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

    # Reconstruct a GeoStats EmpiricalVariogram from our wrapper data.
    # Since we cannot easily construct one directly, we use our own WLS fitting
    # with GeoStats variogram evaluation.

    # Initialise parameters
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

# ── Nelder-Mead simplex optimizer (retained for WLS fitting) ─────────────────

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
