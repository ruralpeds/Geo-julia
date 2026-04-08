# src/regression/spatial_error.jl
# Maximum-likelihood Spatial Error Model (SEM).
# y = Xβ + u,   u = λWu + ε,   ε ~ N(0, σ²I)

using LinearAlgebra, Optim, Statistics

"""
    sem(y, X, w::SpatialWeights; coef_names=nothing) -> SpatialRegResult

Maximum-likelihood estimation of the Spatial Error Model.

The filtered model (A = I - λW) transforms to:
    Ay = AXβ + ε,  ε ~ N(0, σ²I)
so the log-likelihood is log|det(A)| - (n/2)log(σ²) - n/2.

Returns a `SpatialRegResult` with `rho_or_lambda = λ̂`.
"""
function sem(y::Vector{Float64}, X::Matrix{Float64},
              w::SpatialWeights;
              coef_names::Union{Nothing, Vector{Symbol}} = nothing)::SpatialRegResult
    n, k = size(X)
    @assert length(y) == n "y length must match X rows"

    W      = Matrix{Float64}(w.W)
    eigs_W = real.(eigvals(W))

    function neg_ll(λ::Float64)
        A    = I(n) - λ * W
        Ay   = A * y
        AX   = A * X
        β    = AX \ Ay
        e    = Ay - AX * β
        σ2   = dot(e, e) / n
        σ2 > 0 || return Inf
        log_det_A = sum(log.(abs.(1.0 .- λ .* eigs_W)))
        -( log_det_A - (n/2)*log(2π*σ2) - n/2 )
    end

    result  = optimize(neg_ll, -0.99, 0.99, Brent())
    λ_hat   = Optim.minimizer(result)

    A_hat   = I(n) - λ_hat * W
    Ay_hat  = A_hat * y
    AX_hat  = A_hat * X
    β_hat   = AX_hat \ Ay_hat
    e_hat   = Ay_hat - AX_hat * β_hat
    ll_hat  = -Optim.minimum(result)
    ŷ       = X * β_hat   # GLS fitted values (without spatial error)

    names  = isnothing(coef_names) ?
                 Tuple(Symbol("β$(i)") for i in 1:k) :
                 Tuple(coef_names)
    coefs  = NamedTuple{names}(Tuple(β_hat))
    lm     = (LM_lag = NaN, p_lag = NaN, LM_err = NaN, p_err = NaN)

    SpatialRegResult(
        :SEM, coefs, λ_hat, ll_hat,
        _aic(ll_hat, k + 2), _bic(ll_hat, k + 2, n),
        lm, e_hat, ŷ,
    )
end
