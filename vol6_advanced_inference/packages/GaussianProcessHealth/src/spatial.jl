# spatial.jl — Spatial GP interpolation utilities
# Chapter 44.4

"""
    spatial_gp_surface(model, lat_range, lon_range; nx, ny)
                      -> DataFrame

Evaluate GP posterior mean and std on a regular grid.
Returns DataFrame with: lat, lon, mean, std, lower_95, upper_95.
"""
function spatial_gp_surface(model     ::GPModel,
                             lat_range ::Tuple{Float64,Float64},
                             lon_range ::Tuple{Float64,Float64};
                             nx::Int   = 30,
                             ny::Int   = 30)
    lats = range(lat_range[1], lat_range[2]; length=ny)
    lons = range(lon_range[1], lon_range[2]; length=nx)
    grid_pts = [[lat, lon] for lat in lats for lon in lons]
    X_grid   = Float64.(hcat(first.(grid_pts), last.(grid_pts)))
    μ, v, σ  = gp_predict(model, X_grid)

    DataFrame(
        lat      = X_grid[:, 1],
        lon      = X_grid[:, 2],
        mean     = μ,
        std      = σ,
        lower_95 = μ .- 1.96 .* σ,
        upper_95 = μ .+ 1.96 .* σ,
    )
end

"""
    uncertainty_map(model, X_candidates) -> Vector{Float64}

Active learning utility: return predictive std at candidate locations.
Use to select the next observation point that maximally reduces uncertainty.
"""
function uncertainty_map(model        ::GPModel,
                          X_candidates ::AbstractMatrix)::Vector{Float64}
    _, _, σ = gp_predict(model, X_candidates)
    σ
end

"""
    exceedance_probability(model, X_star, threshold) -> Vector{Float64}

P(f(x*) > threshold | y): probability that access score exceeds threshold.
Uses Gaussian tail probability of posterior predictive.
"""
function exceedance_probability(model    ::GPModel,
                                 X_star  ::AbstractMatrix,
                                 threshold::Float64)::Vector{Float64}
    μ, v, σ = gp_predict(model, X_star)
    # P(f > threshold) = 1 - Φ((threshold - μ) / σ)
    Distributions.ccdf.(Normal.(μ, max.(σ, 1e-9)), threshold)
end

"""
    leave_one_out_cv(kernel, X, y; σ²_noise, dist_fn) -> NamedTuple

Leave-one-out cross-validation via Cholesky update formula:
  loo_mean_i    = yᵢ - α_i / [K + σ²I]⁻¹_{ii}
  loo_var_i     = 1 / [K + σ²I]⁻¹_{ii}
  loo_log_lik   = -½ Σ_i [ (yᵢ - μ_i)²/v_i + log(v_i) + log(2π) ]

O(n³) one-time cost; no re-fitting needed.
"""
function leave_one_out_cv(kernel   ::GPKernel,
                           X        ::AbstractMatrix,
                           y        ::AbstractVector;
                           σ²_noise ::Float64   = 0.01,
                           dist_fn  ::Function  = (a,b) -> norm(a.-b))
    model  = gp_fit(X, y, kernel; σ²_noise=σ²_noise, dist_fn=dist_fn)
    α      = model.α
    L      = model.L
    K_inv  = model.L' \ (model.L \ I)  # n × n inverse
    n      = length(y)

    loo_μ  = Float64.(y) .- α ./ diag(K_inv)
    loo_v  = 1.0 ./ max.(diag(K_inv), 1e-12)
    loo_ll = -0.5 * sum(((Float64.(y) .- loo_μ).^2) ./ loo_v .+ log.(loo_v) .+ log(2π))
    rmse   = sqrt(mean((Float64.(y) .- loo_μ).^2))

    (loo_means=loo_μ, loo_vars=loo_v, loo_log_lik=loo_ll, rmse=rmse)
end

using Distributions: Normal, ccdf
