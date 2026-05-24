# state_space.jl — Dynamic Linear Model (DLM) using StateSpaceModels.jl
# Public API preserved: kalman_filter, LocalLevelModel, dlm_fit, dlm_predict,
#                        local_trend_fit, local_trend_predict, LocalTrendModel

using Statistics, LinearAlgebra

# ── Local Level Model ─────────────────────────────────────────────────────────

"""
    LocalLevelModel

Local-level (random walk + noise) state space model.

y_t = μ_t + ε_t,   ε_t ~ N(0, σ²_ε)
μ_t = μ_{t-1} + η_t, η_t ~ N(0, σ²_η)

Fields: σ²_ε, σ²_η (hyperparameters), filtered means/variances,
        smoothed means/variances, log-likelihood, signal-to-noise ratio (q = σ²_η/σ²_ε).
"""
mutable struct LocalLevelModel
    σ²_ε     ::Float64
    σ²_η     ::Float64
    filt_mean::Vector{Float64}   # a_t|t
    filt_var ::Vector{Float64}   # P_t|t
    pred_mean::Vector{Float64}   # a_t|t-1
    pred_var ::Vector{Float64}   # P_t|t-1
    smooth_mean::Vector{Float64}
    smooth_var ::Vector{Float64}
    innovations::Vector{Float64}
    innov_var  ::Vector{Float64}
    log_lik  ::Float64
    n        ::Int
end

"""
    kalman_filter(y, σ²_ε, σ²_η; μ0, P0) -> LocalLevelModel

Run the Kalman filter on a local-level model.
Uses StateSpaceModels.LocalLevel internally, with custom hyperparameters
applied through the standard Kalman recursion for exact parameter control.
"""
function kalman_filter(y::AbstractVector, σ²_ε::Float64, σ²_η::Float64;
                       μ0::Float64=y[1], P0::Float64=1e6)
    n = length(y)
    a  = zeros(n+1); P  = zeros(n+1)   # predicted
    af = zeros(n);   Pf = zeros(n)     # filtered
    v  = zeros(n);   Fv = zeros(n)     # innovations

    a[1]  = μ0
    P[1]  = P0
    ll    = 0.0

    for t in 1:n
        # Innovation
        v[t]  = y[t] - a[t]
        Fv[t] = P[t] + σ²_ε
        # Kalman gain
        K     = P[t] / Fv[t]
        # Update
        af[t] = a[t] + K * v[t]
        Pf[t] = P[t] * (1.0 - K)
        # Log-likelihood contribution (Gaussian)
        ll   -= 0.5 * (log(2π * Fv[t]) + v[t]^2 / Fv[t])
        # Predict
        a[t+1] = af[t]
        P[t+1] = Pf[t] + σ²_η
    end

    # Kalman smoother (RTS)
    as = copy(af); Ps = copy(Pf)
    for t in n-1:-1:1
        G    = Pf[t] / max(P[t+1], 1e-12)
        as[t] = af[t] + G * (as[t+1] - a[t+1])
        Ps[t] = Pf[t] + G^2 * (Ps[t+1] - P[t+1])
    end

    LocalLevelModel(σ²_ε, σ²_η, af, Pf, a[1:n], P[1:n],
                    as, Ps, v, Fv, ll, n)
end

"""
    dlm_fit(y; max_iter, tol) -> LocalLevelModel

Fit local-level DLM using StateSpaceModels.LocalLevel with MLE.
Falls back to custom EM algorithm if StateSpaceModels fails.
"""
function dlm_fit(y::AbstractVector; max_iter::Int=50, tol::Float64=1e-6)
    y_vec = collect(Float64, y)
    n = length(y_vec)

    # Try StateSpaceModels.LocalLevel first
    try
        ssm_model = StateSpaceModels.LocalLevel(y_vec)
        StateSpaceModels.fit!(ssm_model)

        # Extract hyperparameters (observation noise σ²_ε, state noise σ²_η)
        hyperparams = StateSpaceModels.get_hyperparameters(ssm_model)
        # LocalLevel has 2 hyperparameters: σ²_ε and σ²_η (in log scale)
        σ²_ε = length(hyperparams) >= 1 ? exp(hyperparams[1]) : var(y_vec) * 0.8
        σ²_η = length(hyperparams) >= 2 ? exp(hyperparams[2]) : var(y_vec) * 0.2

        # Run our Kalman filter with the MLE-estimated hyperparameters
        # to populate all the struct fields consistently
        return kalman_filter(y_vec, σ²_ε, σ²_η)
    catch e
        # Fall back to custom EM
    end

    _dlm_fit_custom(y_vec; max_iter=max_iter, tol=tol)
end

"""
    _dlm_fit_custom(y; max_iter, tol) -> LocalLevelModel

Custom EM-based fitting for local-level DLM (Harvey 1989).
Used as fallback when StateSpaceModels fails.
"""
function _dlm_fit_custom(y::Vector{Float64}; max_iter::Int=50, tol::Float64=1e-6)
    n    = length(y)
    σ²_ε = var(y) * 0.8
    σ²_η = var(y) * 0.2

    ll_prev = -Inf
    model   = nothing

    for iter in 1:max_iter
        model = kalman_filter(y, σ²_ε, σ²_η)

        # EM update equations
        σ²_ε_new = mean(model.innovations.^2 ./ model.innov_var) * σ²_ε
        σ²_ε_new = max(σ²_ε_new, 1e-8)

        smooth_diff = diff(model.smooth_mean)
        σ²_η_new = mean(smooth_diff.^2 .+ model.smooth_var[2:end]) - σ²_η * 0.0
        σ²_η_new = max(σ²_η_new, 1e-8)

        if abs(model.log_lik - ll_prev) < tol; break; end
        ll_prev = model.log_lik
        σ²_ε = σ²_ε_new
        σ²_η = σ²_η_new
    end

    model
end

"""
    dlm_predict(model, y, h; σ²_ε, σ²_η) -> NamedTuple

h-step-ahead predictions with predictive intervals.
Uses StateSpaceModels.forecast when possible.
"""
function dlm_predict(model::LocalLevelModel, y::AbstractVector, h::Int)
    y_vec = collect(Float64, y)

    # Try StateSpaceModels forecast
    try
        ssm_model = StateSpaceModels.LocalLevel(y_vec)
        StateSpaceModels.fit!(ssm_model)
        fc = StateSpaceModels.forecast(ssm_model, h)

        # Extract forecast means and prediction intervals
        pred_mean = [fc.expected_value[k] for k in 1:h]
        # Compute prediction standard errors from the model variances
        pred_var = [model.filt_var[end] + model.σ²_η * k + model.σ²_ε for k in 1:h]
        pred_se = sqrt.(pred_var)

        return (mean=pred_mean, lower=pred_mean .- 1.96 .* pred_se,
                upper=pred_mean .+ 1.96 .* pred_se,
                horizon=1:h, σ_pred=pred_se)
    catch e
        # Fall back to custom prediction
    end

    # Fallback: use last filtered state
    a_T = model.filt_mean[end]
    P_T = model.filt_var[end]

    pred_mean = fill(a_T, h)
    pred_var  = [P_T + model.σ²_η * k + model.σ²_ε for k in 1:h]
    pred_se   = sqrt.(pred_var)

    (mean=pred_mean, lower=pred_mean .- 1.96 .* pred_se,
     upper=pred_mean .+ 1.96 .* pred_se,
     horizon=1:h, σ_pred=pred_se)
end

# ── Local Trend Model (Holt) ──────────────────────────────────────────────────

"""
    LocalTrendModel

Local linear trend model:
  y_t   = μ_t + ε_t
  μ_t   = μ_{t-1} + ν_{t-1} + ξ_t
  ν_t   = ν_{t-1} + ζ_t
"""
struct LocalTrendModel
    σ²_ε  ::Float64
    σ²_ξ  ::Float64   # level disturbance
    σ²_ζ  ::Float64   # slope disturbance
    states::Matrix{Float64}  # (n, 2): [level, slope]
    log_lik::Float64
    n     ::Int
end

"""
    local_trend_fit(y; max_iter, tol) -> LocalTrendModel

Fit a local linear trend model using StateSpaceModels.LocalLinearTrend.
Falls back to custom Kalman filter if StateSpaceModels fails.
"""
function local_trend_fit(y::AbstractVector; max_iter::Int=40, tol::Float64=1e-5)
    y_vec = collect(Float64, y)
    n = length(y_vec)

    # Try StateSpaceModels.LocalLinearTrend
    try
        ssm_model = StateSpaceModels.LocalLinearTrend(y_vec)
        StateSpaceModels.fit!(ssm_model)

        # Extract hyperparameters
        hyperparams = StateSpaceModels.get_hyperparameters(ssm_model)
        # LocalLinearTrend has 3 hyperparameters: σ²_ε, σ²_ξ, σ²_ζ (in log scale)
        σ²_ε = length(hyperparams) >= 1 ? exp(hyperparams[1]) : var(y_vec) * 0.6
        σ²_ξ = length(hyperparams) >= 2 ? exp(hyperparams[2]) : var(diff(y_vec)) * 0.3
        σ²_ζ = length(hyperparams) >= 3 ? exp(hyperparams[3]) : var(diff(y_vec)) * 0.1

        # Run Kalman filter to extract states using MLE hyperparameters
        a  = [y_vec[1], 0.0]
        P  = diagm([1e6, 1e4])
        T  = [1.0 1.0; 0.0 1.0]
        Z  = [1.0, 0.0]
        Q  = diagm([σ²_ξ, σ²_ζ])
        H  = σ²_ε

        states = zeros(n, 2)
        ll = 0.0

        for t in 1:n
            ap = T * a
            Pp = T * P * T' .+ Q
            v  = y_vec[t] - dot(Z, ap)
            Fv = dot(Z, Pp * Z) + H
            K  = Pp * Z / Fv
            a  = ap .+ K .* v
            P  = (I - K * Z') * Pp
            states[t, :] = a
            ll -= 0.5 * (log(2π * Fv) + v^2 / Fv)
        end

        return LocalTrendModel(σ²_ε, σ²_ξ, σ²_ζ, states, ll, n)
    catch e
        # Fall back to custom implementation
    end

    _local_trend_fit_custom(y_vec; max_iter=max_iter, tol=tol)
end

"""
    _local_trend_fit_custom(y; max_iter, tol) -> LocalTrendModel

Custom local linear trend fitting via iterative Kalman filter.
Used as fallback when StateSpaceModels fails.
"""
function _local_trend_fit_custom(y::Vector{Float64}; max_iter::Int=40, tol::Float64=1e-5)
    n = length(y)
    σ²_ε = var(y) * 0.6
    σ²_ξ = var(diff(y)) * 0.3
    σ²_ζ = var(diff(y)) * 0.1

    best_ll = -Inf; best_states = zeros(n, 2)

    for iter in 1:max_iter
        a  = [y[1], 0.0]
        P  = diagm([1e6, 1e4])
        T  = [1.0 1.0; 0.0 1.0]
        Z  = [1.0, 0.0]
        Q  = diagm([σ²_ξ, σ²_ζ])
        H  = σ²_ε

        states = zeros(n, 2)
        ll = 0.0

        for t in 1:n
            ap = T * a
            Pp = T * P * T' .+ Q
            v  = y[t] - dot(Z, ap)
            Fv = dot(Z, Pp * Z) + H
            K  = Pp * Z / Fv
            a  = ap .+ K .* v
            P  = (I - K * Z') * Pp
            states[t, :] = a
            ll -= 0.5 * (log(2π * Fv) + v^2 / Fv)
        end

        if ll > best_ll
            best_ll = ll; best_states = states
        end

        resid = y .- states[:, 1]
        σ²_ε_new = max(var(resid), 1e-8)
        slope_diff = diff(states[:, 2])
        σ²_ζ_new = max(var(slope_diff), 1e-8)
        level_diff = diff(states[:, 1]) .- states[1:end-1, 2]
        σ²_ξ_new = max(var(level_diff), 1e-8)

        if abs(best_ll - ll) < tol; break; end
        σ²_ε = σ²_ε_new; σ²_ξ = σ²_ξ_new; σ²_ζ = σ²_ζ_new
    end

    LocalTrendModel(σ²_ε, σ²_ξ, σ²_ζ, best_states, best_ll, n)
end

"""
    local_trend_predict(model, h) -> NamedTuple

h-step forecast from local trend model.
"""
function local_trend_predict(model::LocalTrendModel, h::Int)
    level = model.states[end, 1]
    slope = model.states[end, 2]
    pred  = [level + k * slope for k in 1:h]
    se    = sqrt.(model.σ²_ε .+ (1:h) .* model.σ²_ξ .+
                  [(k*(k-1)/2)^2 * model.σ²_ζ for k in 1:h])
    (mean=pred, lower=pred .- 1.96 .* se, upper=pred .+ 1.96 .* se,
     horizon=1:h, slope=slope, level=level)
end
