# spatial_lag.jl — Spatial lag model for SpatialRegression
# Chapter 49 — Open-Source Healthcare GIS Textbook in Julia
#
# Spatial lag model: Y = ρWY + Xβ + ε,  ε ~ N(0, σ²I)
# Reduced form: Y = (I - ρW)⁻¹Xβ + (I - ρW)⁻¹ε
# OLS is biased for ρ; use Maximum Likelihood via eigenvalue decomposition.
#
# log L = -n/2·log(2π) - n/2·log(σ²) + log|I - ρW|
#          - 1/(2σ²)·(y - ρWy - Xβ)'(y - ρWy - Xβ)
#
# LeSage & Pace (2009), Anselin (1988)

"""
    SpatialLagModel

Spatial lag model: Y = ρWY + Xβ + ε
"""
struct SpatialLagModel
    ρ            :: Float64          # spatial autoregressive parameter
    β            :: Vector{Float64}  # (p+1) including intercept
    σ²           :: Float64
    se_ρ         :: Float64
    se_β         :: Vector{Float64}
    t_stats      :: Vector{Float64}  # β first, then ρ
    log_lik      :: Float64
    aic          :: Float64
    bic          :: Float64
    residuals    :: Vector{Float64}
    fitted       :: Vector{Float64}
    feature_names :: Vector{String}
    W            :: Matrix{Float64}
    n            :: Int
    converged    :: Bool
end

"""
    spatial_lag_fit(y, X, W; ρ_init, tol, max_iter) -> SpatialLagModel

Fit a spatial lag model via concentrated ML.
Profile out β and σ² analytically; optimise over ρ ∈ (-1,1).

For a given ρ:
  β(ρ)  = (X'X)⁻¹ X'(y - ρWy)   [OLS on spatially lagged residuals]
  σ²(ρ) = RSS(ρ) / n
  log L(ρ) = log|I - ρW| - n/2 log(RSS(ρ))  [+ constants]
"""
function spatial_lag_fit(
    y       :: AbstractVector{<:Real},
    X       :: AbstractMatrix{<:Real},
    W       :: AbstractMatrix{<:Real};
    ρ_init  :: Float64 = 0.1,
    tol     :: Float64 = 1e-6,
    max_iter :: Int    = 100,
    feature_names :: Vector{String} = String[],
)
    n, p = size(X)
    if isempty(feature_names)
        feature_names = ["intercept"; ["x$(i)" for i in 1:p]]
    else
        feature_names = ["intercept"; feature_names]
    end

    X_aug = hcat(ones(n), X)
    Wy    = W * y
    XtXinv = (X_aug' * X_aug + 1e-8I) \ I(p+1)

    # Eigenvalues of W for fast log|I - ρW| = Σ log(1 - ρλ_i)
    W_sym = (W + W') ./ 2   # symmetrise for real eigenvalues
    eigs_W = eigvals(Symmetric(W_sym))

    # Concentrated log-likelihood (up to constants)
    function log_lik_concentrated(ρ::Float64)
        abs(ρ) >= 0.999 && return -Inf
        if any(1 - ρ*λ <= 0 for λ in eigs_W)
            return -Inf
        end
        log_det = sum(log(1 - ρ*λ) for λ in eigs_W)

        y_star  = y .- ρ .* Wy
        β_ρ     = XtXinv * (X_aug' * y_star)
        e_ρ     = y_star .- X_aug * β_ρ
        rss_ρ   = sum(e_ρ.^2)
        σ²_ρ    = rss_ρ / n
        σ²_ρ < 1e-12 && return -Inf

        log_det - n/2 * log(σ²_ρ)
    end

    # Optimise ρ ∈ (-0.99, 0.99) using Optim.jl Brent's method
    # Minimise negative concentrated log-likelihood
    result = Optim.optimize(ρ -> -log_lik_concentrated(ρ), -0.99, 0.99, Optim.Brent())
    converged = Optim.converged(result)
    ρ_opt = Optim.minimizer(result)
    y_star = y .- ρ_opt .* Wy
    β_opt  = XtXinv * (X_aug' * y_star)
    e_opt  = y_star .- X_aug * β_opt
    σ²_opt = sum(e_opt.^2) / n

    fitted    = ρ_opt .* Wy .+ X_aug * β_opt
    residuals = y .- fitted

    # Log-likelihood (full)
    log_det = sum(log(1 - ρ_opt*λ) for λ in eigs_W)
    ll = log_det - n/2*log(2π*σ²_opt) - sum(e_opt.^2)/(2*σ²_opt)

    k_params = p + 3  # β (p+1) + ρ + σ²
    aic = -2*ll + 2*k_params
    bic = -2*ll + k_params*log(n)

    # Approximate SEs via OPG/sandwich (simplified: OLS SEs as lower bound)
    XtX_inv = (X_aug' * X_aug + 1e-8I) \ I(p+1)
    se_β    = sqrt.(max.(diag(σ²_opt .* XtX_inv), 0.0))

    # SE for ρ via numerical Hessian
    h = 1e-4
    ll_p = log_lik_concentrated(ρ_opt + h)
    ll_m = log_lik_concentrated(ρ_opt - h)
    ll_0 = log_lik_concentrated(ρ_opt)
    hess_ρ = (ll_p - 2*ll_0 + ll_m) / h^2
    se_ρ   = hess_ρ < -1e-12 ? sqrt(-1.0/hess_ρ) : 0.1

    t_β = β_opt ./ max.(se_β, 1e-12)
    t_ρ = ρ_opt / max(se_ρ, 1e-12)
    t_all = vcat(t_β, t_ρ)

    SpatialLagModel(ρ_opt, β_opt, σ²_opt, se_ρ, se_β, t_all,
                    ll, aic, bic, residuals, fitted, feature_names,
                    Matrix(W), n, converged)
end

function Base.show(io::IO, m::SpatialLagModel)
    println(io, "SpatialLagModel (n=$(m.n))")
    println(io, "  ρ (spatial lag): $(round(m.ρ; digits=4)) (se=$(round(m.se_ρ;digits=4)))")
    println(io, "  Coefficients:")
    for (i, nm) in enumerate(m.feature_names)
        println(io, "    $(rpad(nm,15)) β=$(round(m.β[i];digits=4))")
    end
    println(io, "  σ²=$(round(m.σ²;digits=5))")
    println(io, "  AIC=$(round(m.aic;digits=2)), BIC=$(round(m.bic;digits=2))")
    print(io,   "  Log-lik=$(round(m.log_lik;digits=2))")
end
