# regression/spatial_lag.jl — Spatial Lag Model (SAR/SLM)

using LinearAlgebra
using Optim

"""
    slm(y, X, w; coef_names) -> SpatialRegResult

Spatial Lag Model: y = ρWy + Xβ + ε, ε ~ N(0, σ²I)

Maximum likelihood estimation using the Ord (1975) eigenvalue approach:
  log|I - ρW| = Σ log|1 - ρ·eig_i(W)|

This avoids computing the determinant of (I - ρW) directly,
reducing cost from O(n³) to O(n) once eigenvalues are pre-computed.

# Arguments
- `y`          : response vector (n,)
- `X`          : design matrix (n × k)
- `w`          : `SpatialWeights`
- `coef_names` : optional names for coefficients
"""
function slm(y::AbstractVector{<:Real},
              X::AbstractMatrix{<:Real},
              w::AbstractSpatialWeights;
              coef_names::Union{Nothing, Vector{String}} = nothing)::SpatialRegResult

    n, k = size(X)
    yf   = Float64.(y)
    Xf   = Float64.(X)
    W    = w.W
    names = coef_names === nothing ? ["x$(i)" for i in 1:k] : coef_names

    # Eigenvalues of W (real, since W is row-standardised and symmetric-like)
    # Use dense for small n; for large n consider Arpack.jl
    W_dense = Matrix(W)
    eigs_W  = real.(eigvals(W_dense))

    # Constrain ρ to (1/min_eig, 1/max_eig) for stationarity
    eig_max  = maximum(eigs_W)
    eig_min  = minimum(eigs_W)
    ρ_lo = (eig_min < 0 ? 1.0 / eig_min + 1e-6 : -0.99)
    ρ_hi = 1.0 / eig_max - 1e-6

    Wy = W * yf

    # Negative log-likelihood for ρ (profile out β and σ²)
    function neg_ll(ρ::Float64)
        S = yf - ρ .* Wy         # (I - ρW)y
        β = Xf \ S               # OLS on transformed y
        e = S - Xf * β
        σ² = dot(e, e) / n
        σ² <= 0 && return Inf
        log_det = sum(log(abs(1.0 - ρ * λ)) for λ in eigs_W)
        -log_det + n/2 * log(σ²)  # minimise → maximise LL
    end

    res  = optimize(neg_ll, ρ_lo, ρ_hi, Brent())
    ρ_ml = Optim.minimizer(res)

    # Recover β, σ², LL at ρ̂
    S    = yf - ρ_ml .* Wy
    β    = Xf \ S
    e    = S - Xf * β          # generalised residuals
    σ²   = dot(e, e) / n
    ŷ    = Xf * β + ρ_ml .* Wy

    log_det = sum(log(abs(1.0 - ρ_ml * λ)) for λ in eigs_W)
    ll      = log_det - n/2 * log(2π * σ²) - n/2
    aic     = -2ll + 2(k + 2)    # +2 for ρ and σ²
    bic     = -2ll + (k + 2) * log(n)

    ss_res  = dot(e, e)
    ss_tot  = dot(yf .- mean(yf), yf .- mean(yf))
    r2      = 1.0 - ss_res / max(ss_tot, 1e-15)

    SpatialRegResult(:SLM, β, names, ρ_ml, ll, aic, bic,
                     0.0, 1.0, 0.0, 1.0,
                     e, ŷ, n, k, r2)
end
