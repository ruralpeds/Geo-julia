# regression/spatial_error.jl — Spatial Error Model (SEM)

using LinearAlgebra
using Optim

"""
    sem(y, X, w; coef_names) -> SpatialRegResult

Spatial Error Model: y = Xβ + u, u = λWu + ε

Equivalent to: (I - λW)y = (I - λW)Xβ + ε
i.e., Cochranne-Orcutt spatial filter.

ML via profile likelihood: for each λ, filter y and X by (I - λW),
then solve OLS.

# Arguments
- `y`          : response vector (n,)
- `X`          : design matrix (n × k)
- `w`          : `SpatialWeights`
- `coef_names` : optional names for coefficients
"""
function sem(y::AbstractVector{<:Real},
              X::AbstractMatrix{<:Real},
              w::AbstractSpatialWeights;
              coef_names::Union{Nothing, Vector{String}} = nothing)::SpatialRegResult

    n, k = size(X)
    yf   = Float64.(y)
    Xf   = Float64.(X)
    W    = w.W
    names = coef_names === nothing ? ["x$(i)" for i in 1:k] : coef_names

    W_dense = Matrix(W)
    eigs_W  = real.(eigvals(W_dense))
    eig_max = maximum(eigs_W)
    eig_min = minimum(eigs_W)
    λ_lo = (eig_min < 0 ? 1.0 / eig_min + 1e-6 : -0.99)
    λ_hi = 1.0 / eig_max - 1e-6

    Wy = W * yf
    WX = Matrix(W * Xf)  # n × k

    function neg_ll(λ::Float64)
        # Filter: ỹ = y - λWy, X̃ = X - λWX
        ỹ = yf - λ .* Wy
        X̃ = Xf - λ .* WX
        β = X̃ \ ỹ
        e = ỹ - X̃ * β
        σ² = dot(e, e) / n
        σ² <= 0 && return Inf
        log_det = sum(log(abs(1.0 - λ * eig)) for eig in eigs_W)
        -log_det + n/2 * log(σ²)
    end

    res  = optimize(neg_ll, λ_lo, λ_hi, Brent())
    λ_ml = Optim.minimizer(res)

    # Recover at λ̂
    ỹ = yf - λ_ml .* Wy
    X̃ = Xf - λ_ml .* WX
    β = X̃ \ ỹ
    e_filtered = ỹ - X̃ * β
    ŷ = Xf * β                   # predicted y in original space
    e = yf - ŷ                   # residuals in original space

    σ² = dot(e_filtered, e_filtered) / n
    log_det = sum(log(abs(1.0 - λ_ml * eig)) for eig in eigs_W)
    ll  = log_det - n/2 * log(2π * σ²) - n/2
    aic = -2ll + 2(k + 2)
    bic = -2ll + (k + 2) * log(n)

    ss_res = dot(e, e)
    ss_tot = dot(yf .- mean(yf), yf .- mean(yf))
    r2 = 1.0 - ss_res / max(ss_tot, 1e-15)

    SpatialRegResult(:SEM, β, names, λ_ml, ll, aic, bic,
                     0.0, 1.0, 0.0, 1.0,
                     e, ŷ, n, k, r2)
end
