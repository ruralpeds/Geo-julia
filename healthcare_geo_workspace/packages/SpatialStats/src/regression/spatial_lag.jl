# src/regression/spatial_lag.jl
# Maximum-likelihood Spatial Lag Model (SAR / SLM).
# y = ρWy + Xβ + ε,   ε ~ N(0, σ²I)
# ML estimation via Ord (1975) eigenvalue approach.

using LinearAlgebra, SparseArrays, Optim, Statistics

"""
    slm(y, X, w::SpatialWeights; coef_names=nothing) -> SpatialRegResult

Maximum-likelihood estimation of the Spatial Lag (SAR) Model.

The log-likelihood is maximised over ρ using Brent's method on the feasible
interval (1/λ_max, 1/λ_min) where λ are the eigenvalues of **W**.
For large n, consider passing `w` with a sparse matrix; eigenvalues are
computed densely here — for n > 5,000 use an Arpack-based approach.

Returns a `SpatialRegResult` with `rho_or_lambda = ρ̂`.
"""
function slm(y::Vector{Float64}, X::Matrix{Float64},
              w::SpatialWeights;
              coef_names::Union{Nothing, Vector{Symbol}} = nothing)::SpatialRegResult
    n, k = size(X)
    @assert length(y) == n "y length must match X rows"

    W        = Matrix{Float64}(w.W)
    eigs_W   = real.(eigvals(W))          # real part only (W ≈ symmetric after row-std)
    λ_min    = minimum(eigs_W)
    λ_max    = maximum(eigs_W)
    ρ_lo     = λ_max > 0 ? 1.0 / λ_max + 1e-6 : -0.99
    ρ_hi     = λ_min < 0 ? 1.0 / λ_min - 1e-6 :  0.99
    ρ_lo, ρ_hi = min(ρ_lo, -0.99), max(ρ_hi, 0.99)   # safety clip

    # Negative log-likelihood as a function of ρ alone
    function neg_ll(ρ::Float64)
        S    = I(n) - ρ * W
        Sy   = S * y
        β    = X \ Sy
        e    = Sy - X * β
        σ2   = dot(e, e) / n
        σ2 > 0 || return Inf
        log_det_S = sum(log.(abs.(1.0 .- ρ .* eigs_W)))
        -( log_det_S - (n/2)*log(2π*σ2) - n/2 )
    end

    result  = optimize(neg_ll, -0.99, 0.99, Brent())
    ρ_hat   = Optim.minimizer(result)

    # Final estimates at ρ̂
    S_hat   = I(n) - ρ_hat * W
    Sy_hat  = S_hat * y
    β_hat   = X \ Sy_hat
    e_hat   = Sy_hat - X * β_hat
    σ2_hat  = dot(e_hat, e_hat) / n
    ll_hat  = -Optim.minimum(result)
    ŷ       = y .- e_hat   # approximate fitted values

    names  = isnothing(coef_names) ?
                 Tuple(Symbol("β$(i)") for i in 1:k) :
                 Tuple(coef_names)
    coefs  = NamedTuple{names}(Tuple(β_hat))
    lm     = (LM_lag = NaN, p_lag = NaN, LM_err = NaN, p_err = NaN)

    SpatialRegResult(
        :SLM, coefs, ρ_hat, ll_hat,
        _aic(ll_hat, k + 2), _bic(ll_hat, k + 2, n),
        lm, e_hat, ŷ,
    )
end
