# forecast.jl — Forecasting from ARIMA / DLM with prediction intervals
# Rolling cross-validation, coverage diagnostics

using Statistics, LinearAlgebra, Random

# ── ARIMA forecasting ─────────────────────────────────────────────────────────

"""
    ARIMAForecast

h-step-ahead ARIMA forecast.
"""
struct ARIMAForecast
    h        ::Int
    point    ::Vector{Float64}
    lower_80 ::Vector{Float64}
    upper_80 ::Vector{Float64}
    lower_95 ::Vector{Float64}
    upper_95 ::Vector{Float64}
    model    ::ARIMAModel
end

"""
    arima_forecast(model, h) -> ARIMAForecast

Generate h-step-ahead point forecasts and Gaussian prediction intervals
from a fitted ARIMA model.
"""
function arima_forecast(model::ARIMAModel, h::Int)
    p  = model.p; q  = model.q
    φ  = model.φ; θ  = model.θ

    # History for AR part (differenced series)
    y_orig  = model.y_orig
    y_diff  = difference(y_orig, model.d)
    n       = length(y_diff)
    yd_c    = y_diff .- model.μ   # centred

    # Extend with forecasts
    y_ext   = copy(yd_c)
    ε_ext   = _arma_residuals(yd_c, φ, θ)
    ε_ext   = vcat(ε_ext, zeros(h))  # future innovations = 0

    preds_diff = Float64[]
    for s in 1:h
        t  = n + s
        ar = sum(j <= t-1 ? φ[j] * y_ext[t-j] : 0.0 for j in 1:p; init=0.0)
        ma = sum(j <= t-1 ? θ[j] * ε_ext[t-j] : 0.0 for j in 1:q; init=0.0)
        ŷ  = ar + ma
        push!(preds_diff, ŷ)
        push!(y_ext, ŷ)
    end

    preds_diff .+= model.μ  # add back mean

    # Re-integrate
    point_preds = if model.d > 0
        init  = y_orig[end-model.d+1:end]
        base  = vcat(difference(y_orig, model.d), preds_diff)
        full  = undifference(base, y_orig[1:model.d], model.d)
        full[end-h+1:end]
    else
        preds_diff
    end

    # Prediction variance grows with horizon
    σ²_1step = model.σ²
    var_h = [σ²_1step * h_k for h_k in 1:h]  # rough approximation: grows linearly
    se_h  = sqrt.(var_h)

    z80 = 1.2816; z95 = 1.96
    ARIMAForecast(h, point_preds,
                  point_preds .- z80 .* se_h, point_preds .+ z80 .* se_h,
                  point_preds .- z95 .* se_h, point_preds .+ z95 .* se_h,
                  model)
end

# ── Rolling cross-validation ──────────────────────────────────────────────────

"""
    RollingCVResult

Rolling-origin time-series cross-validation.
"""
struct RollingCVResult
    h         ::Int
    rmse      ::Float64
    mae       ::Float64
    coverage_80::Float64
    coverage_95::Float64
    mean_width_95::Float64
    n_folds   ::Int
end

"""
    rolling_cv(y, h; min_train, model_type, step) -> RollingCVResult

Rolling-origin cross-validation for ARIMA or DLM.

`model_type ∈ {:arima, :dlm}`
"""
function rolling_cv(y::AbstractVector, h::Int=1;
                    min_train::Int=max(20, length(y)÷3),
                    model_type::Symbol=:arima,
                    step::Int=1,
                    p::Int=1, d::Int=1, q::Int=0)
    n      = length(y)
    errors = Float64[]
    abs_err = Float64[]
    in_80  = Bool[]
    in_95  = Bool[]
    widths = Float64[]

    for t in min_train:step:n-h
        y_train = y[1:t]
        y_test  = y[t+1:t+h]

        fc = try
            if model_type == :arima
                m = arima_fit(y_train, p, d, q; max_iter=30)
                arima_forecast(m, h)
            else
                m = dlm_fit(y_train; max_iter=20)
                r = dlm_predict(m, y_train, h)
                (point=r.mean, lower_95=r.lower, upper_95=r.upper,
                 lower_80=r.mean .- 1.2816 .* r.σ_pred,
                 upper_80=r.mean .+ 1.2816 .* r.σ_pred)
            end
        catch
            continue
        end

        # Only evaluate first-horizon forecast
        ŷ  = fc.point[1]
        yt = y_test[1]
        push!(errors,  ŷ - yt)
        push!(abs_err, abs(ŷ - yt))
        push!(in_80,   fc.lower_80[1] <= yt <= fc.upper_80[1])
        push!(in_95,   fc.lower_95[1] <= yt <= fc.upper_95[1])
        push!(widths,  fc.upper_95[1] - fc.lower_95[1])
    end

    isempty(errors) && return RollingCVResult(h, NaN, NaN, NaN, NaN, NaN, 0)

    RollingCVResult(h,
                    sqrt(mean(errors.^2)),
                    mean(abs_err),
                    mean(in_80),
                    mean(in_95),
                    mean(widths),
                    length(errors))
end

# ── Bootstrap prediction intervals ───────────────────────────────────────────

"""
    bootstrap_forecast_pi(model, h; n_boot, rng, level) -> NamedTuple

Bootstrap prediction intervals for ARIMA by resampling residuals.
"""
function bootstrap_forecast_pi(model::ARIMAModel, h::Int;
                                n_boot::Int=200,
                                rng::AbstractRNG=Random.GLOBAL_RNG,
                                level::Float64=0.95)
    p  = model.p; q = model.q
    φ  = model.φ; θ = model.θ

    y_diff = difference(model.y_orig, model.d) .- model.μ
    ε_hat  = _arma_residuals(y_diff, φ, θ)
    n      = length(y_diff)

    boot_preds = zeros(n_boot, h)

    for b in 1:n_boot
        # Sample residuals with replacement
        ε_boot = ε_hat[rand(rng, 1:n, h)]
        y_ext  = copy(y_diff)
        ε_ext  = vcat(ε_hat, ε_boot)

        for s in 1:h
            t  = n + s
            ar = sum(j <= t-1 ? φ[j] * y_ext[t-j] : 0.0 for j in 1:p; init=0.0)
            ma = sum(j <= t-1 ? θ[j] * ε_ext[t-j] : 0.0 for j in 1:q; init=0.0)
            ŷ  = ar + ma + ε_boot[s]
            push!(y_ext, ŷ)
            boot_preds[b, s] = ŷ + model.μ
        end
    end

    α = 1.0 - level
    lower = [quantile(boot_preds[:, s], α/2) for s in 1:h]
    upper = [quantile(boot_preds[:, s], 1-α/2) for s in 1:h]
    point = [quantile(boot_preds[:, s], 0.5) for s in 1:h]

    # Reintegrate if d > 0
    if model.d > 0
        init   = model.y_orig[end-model.d+1:end]
        reint  = ts -> undifference(vcat(difference(model.y_orig, model.d), ts),
                                    model.y_orig[1:model.d], model.d)[end-h+1:end]
        point  = reint(point)
        lower  = reint(lower)
        upper  = reint(upper)
    end

    (point=point, lower=lower, upper=upper, level=level, n_boot=n_boot)
end
