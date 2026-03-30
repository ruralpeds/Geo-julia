# regression/spatial_durbin.jl — Spatial Durbin Model (SDM)

"""
    sdm(y, X, w; coef_names) -> SpatialRegResult

Spatial Durbin Model: y = ρWy + Xβ + WXθ + ε

Augments the design matrix with spatially-lagged predictors WX,
then fits an SLM. Returns `:SDM` model type.

Coefficient interpretation:
- First k entries: direct effects β
- Next k entries (or k-1 if intercept excluded from WX): indirect effects θ
- `rho_or_lambda`: ρ

# Arguments
- `y`          : response vector (n,)
- `X`          : design matrix (n × k); should include intercept
- `w`          : `SpatialWeights`
- `coef_names` : optional names; if nothing, auto-generated as "x_i" and "wx_i"
"""
function sdm(y::AbstractVector{<:Real},
              X::AbstractMatrix{<:Real},
              w::AbstractSpatialWeights;
              coef_names::Union{Nothing, Vector{String}} = nothing)::SpatialRegResult

    n, k = size(X)
    Xf   = Float64.(X)
    W    = w.W

    # Spatially lag all columns of X (including intercept column, excluded below)
    # Convention: do not lag the intercept column (first column if all-ones)
    intercept_col = all(Xf[:, 1] .≈ 1.0)
    lag_cols = intercept_col ? (2:k) : (1:k)

    WX = Matrix(W * Xf[:, lag_cols])  # n × length(lag_cols)
    X_aug = hcat(Xf, WX)              # n × (k + length(lag_cols))

    if coef_names === nothing
        base_names = ["x$(i)" for i in 1:k]
        lag_names  = ["Wx$(i)" for i in lag_cols]
        coef_names = vcat(base_names, lag_names)
    end

    # Fit SLM on augmented design matrix
    result = slm(y, X_aug, w; coef_names)

    # Return with :SDM model type
    SpatialRegResult(:SDM,
        result.coefficients, result.coef_names,
        result.rho_or_lambda, result.log_likelihood,
        result.AIC, result.BIC,
        0.0, 1.0, 0.0, 1.0,
        result.residuals, result.fitted,
        result.n, result.k, result.r_squared)
end
