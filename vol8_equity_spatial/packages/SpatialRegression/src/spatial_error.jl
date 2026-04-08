# spatial_error.jl — Spatial error model for SpatialRegression
# Chapter 49 — Open-Source Healthcare GIS Textbook in Julia
#
# Spatial error model: Y = Xβ + u,  u = λWu + ε,  ε ~ N(0, σ²I)
# Equivalent to: Y = Xβ + (I - λW)⁻¹ε
# GLS estimator via Prais-Winsten transformation:
#   β(λ) = (X*'X*)⁻¹X*'y*   where y* = (I-λW)y, X* = (I-λW)X
# Anselin (1988), Kelejian & Prucha (1998)

"""
    SpatialErrorModel

Spatial error model: Y = Xβ + u, u = λWu + ε
"""
struct SpatialErrorModel
    λ            :: Float64          # spatial error parameter
    β            :: Vector{Float64}
    σ²           :: Float64
    se_λ         :: Float64
    se_β         :: Vector{Float64}
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
    spatial_error_fit(y, X, W; tol, max_iter) -> SpatialErrorModel

Fit spatial error model via concentrated ML (profile over λ).
"""
function spatial_error_fit(
    y       :: AbstractVector{<:Real},
    X       :: AbstractMatrix{<:Real},
    W       :: AbstractMatrix{<:Real};
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

    # Eigenvalues for log|I - λW|
    W_sym  = (W + W') ./ 2
    eigs_W = eigvals(Symmetric(W_sym))
    Wy     = W * y

    function log_lik_spatial_error(λ::Float64)
        abs(λ) >= 0.999 && return -Inf
        any(1 - λ*ev <= 0 for ev in eigs_W) && return -Inf

        # Prais-Winsten GLS transformation
        A      = I(n) .- λ .* W
        y_star = A * y
        X_star = A * X_aug

        # OLS on transformed data
        XtX    = X_star' * X_star + 1e-8I(p+1)
        β_λ    = XtX \ (X_star' * y_star)
        e_λ    = y_star .- X_star * β_λ
        σ²_λ   = sum(e_λ.^2) / n
        σ²_λ < 1e-12 && return -Inf

        log_det = sum(log(1 - λ*ev) for ev in eigs_W)
        log_det - n/2 * log(σ²_λ)
    end

    # Golden section search over λ ∈ (-0.99, 0.99)
    λ_lo, λ_hi = -0.99, 0.99
    φ = (sqrt(5) - 1) / 2
    converged = false

    for _ in 1:max_iter
        λ1 = λ_hi - φ * (λ_hi - λ_lo)
        λ2 = λ_lo + φ * (λ_hi - λ_lo)
        if log_lik_spatial_error(λ1) < log_lik_spatial_error(λ2)
            λ_lo = λ1
        else
            λ_hi = λ2
        end
        if λ_hi - λ_lo < tol
            converged = true; break
        end
    end

    λ_opt  = (λ_lo + λ_hi) / 2
    A_opt  = I(n) .- λ_opt .* W
    y_star = A_opt * y
    X_star = A_opt * X_aug
    XtX    = X_star' * X_star + 1e-8I(p+1)
    β_opt  = XtX \ (X_star' * y_star)
    e_opt  = y_star .- X_star * β_opt
    σ²_opt = sum(e_opt.^2) / n

    fitted    = X_aug * β_opt
    residuals = y .- fitted

    # Full log-likelihood
    log_det = sum(log(1 - λ_opt*ev) for ev in eigs_W)
    ll = log_det - n/2*log(2π*σ²_opt) - sum(e_opt.^2)/(2*σ²_opt)

    k_params = p + 3
    aic = -2*ll + 2*k_params
    bic = -2*ll + k_params*log(n)

    # Standard errors
    se_β = sqrt.(max.(diag(σ²_opt .* (XtX \ I(p+1))), 0.0))

    h = 1e-4
    ll_p = log_lik_spatial_error(λ_opt + h)
    ll_m = log_lik_spatial_error(λ_opt - h)
    ll_0 = log_lik_spatial_error(λ_opt)
    hess_λ = (ll_p - 2*ll_0 + ll_m) / h^2
    se_λ   = hess_λ < -1e-12 ? sqrt(-1.0/hess_λ) : 0.1

    SpatialErrorModel(λ_opt, β_opt, σ²_opt, se_λ, se_β,
                      ll, aic, bic, residuals, fitted, feature_names,
                      Matrix(W), n, converged)
end

function Base.show(io::IO, m::SpatialErrorModel)
    println(io, "SpatialErrorModel (n=$(m.n))")
    println(io, "  λ (spatial error): $(round(m.λ; digits=4)) (se=$(round(m.se_λ;digits=4)))")
    println(io, "  Coefficients:")
    for (i, nm) in enumerate(m.feature_names)
        println(io, "    $(rpad(nm,15)) β=$(round(m.β[i];digits=4))")
    end
    println(io, "  AIC=$(round(m.aic;digits=2)), BIC=$(round(m.bic;digits=2))")
    print(io,   "  Log-lik=$(round(m.log_lik;digits=2))")
end
