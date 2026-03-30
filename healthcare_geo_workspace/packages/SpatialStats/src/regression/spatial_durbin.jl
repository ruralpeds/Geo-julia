# src/regression/spatial_durbin.jl
# Spatial Durbin Model (SDM).
# y = ρWy + Xβ + WXθ + ε
# Estimated by augmenting X with WX and fitting SLM.

using LinearAlgebra, Statistics

"""
    sdm(y, X, w::SpatialWeights; coef_names=nothing) -> SpatialRegResult

Estimate the Spatial Durbin Model:

    y = ρ W y + X β + W X θ + ε

The SDM is a generalisation of both SLM and SEM; it nests the SLM when θ = 0
and approximates the SEM when θ = -ρβ (common factor restriction).

Implementation: augment the design matrix with spatially lagged regressors
`WX` and call `slm()` on the augmented system.  The first `k` coefficients
are β (own-unit effects); the next `k` are θ (neighbour effects).
"""
function sdm(y::Vector{Float64}, X::Matrix{Float64},
              w::SpatialWeights;
              coef_names::Union{Nothing, Vector{Symbol}} = nothing)::SpatialRegResult
    n, k = size(X)
    W    = Matrix{Float64}(w.W)
    WX   = W * X
    X_aug = hcat(X, WX)   # n × 2k

    aug_names = if isnothing(coef_names)
        vcat([Symbol("β$(i)") for i in 1:k],
             [Symbol("θ$(i)") for i in 1:k])
    else
        vcat(coef_names, [Symbol("W_$(n)") for n in coef_names])
    end

    result = slm(y, X_aug, w; coef_names = aug_names)
    SpatialRegResult(:SDM, result.coefficients, result.rho_or_lambda,
                     result.log_likelihood, result.AIC, result.BIC,
                     result.lm_tests, result.residuals, result.fitted)
end
