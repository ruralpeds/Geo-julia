# report.jl — TimeSeriesHealth report

using Statistics

"""
    TimeSeriesReport

Comprehensive time-series analysis report.
"""
struct TimeSeriesReport
    series_name    ::String
    n              ::Int
    mean_val       ::Float64
    trend          ::Float64   # slope from linear regression
    acf_lag1       ::Float64
    arima_order    ::Tuple{Int,Int,Int}
    arima_aic      ::Float64
    dlm_loglik     ::Float64
    cusum_alarms   ::Int
    farrington_alarms::Int
    ewma_alarms    ::Int
    forecast_h     ::Int
    forecast_point ::Vector{Float64}
    cv_rmse        ::Float64
    timestamp      ::String
end

"""
    ts_report(y; series_name, h_forecast, run_cv) -> TimeSeriesReport

Run a complete time-series analysis pipeline.
"""
function ts_report(y::AbstractVector;
                   series_name::String="HealthTimeSeries",
                   h_forecast::Int=4,
                   run_cv::Bool=true,
                   period::Int=52,
                   n_years_far::Int=2)
    n    = length(y)
    μ    = mean(y)
    acf1 = acf(y, 1)[2]

    # Linear trend
    t    = collect(1.0:n)
    β1   = cov(t, y) / var(t)

    # ARIMA
    arima_m = auto_arima(y; max_p=2, max_q=1, d=1, max_iter=40)
    fc      = arima_forecast(arima_m, h_forecast)

    # DLM
    dlm_m = dlm_fit(y; max_iter=30)

    # Outbreak detection
    cusum_r = cusum_detect(Float64.(y); μ0=Float64(μ),
                            σ0=Float64(std(y)) + 1e-8)
    ewma_r  = poisson_ewma(Float64.(y))

    # Farrington (requires sufficient history)
    far_alarms = 0
    if n > n_years_far * period
        far_r = farrington_detect(Float64.(y);
                                   n_years=n_years_far, period=period)
        far_alarms = sum(far_r.alarms)
    end

    # Cross-validation
    cv_rmse = NaN
    if run_cv && n > 30
        cv = rolling_cv(y, 1; min_train=max(15, n÷3), model_type=:arima, step=2)
        cv_rmse = cv.rmse
    end

    TimeSeriesReport(series_name, n, μ, β1, acf1,
                     (arima_m.p, arima_m.d, arima_m.q),
                     arima_m.aic, dlm_m.log_lik,
                     sum(cusum_r.alarms), far_alarms, sum(ewma_r.alarms),
                     h_forecast, fc.point, cv_rmse,
                     "2026-01-01")
end

"""
    print_ts_report(r)
"""
function print_ts_report(r::TimeSeriesReport)
    println("=" ^ 60)
    println("  Time-Series Report: $(r.series_name)")
    println("=" ^ 60)
    println("  N=$(r.n)  Mean=$(round(r.mean_val,digits=2))  ACF(1)=$(round(r.acf_lag1,digits=3))")
    println("  Trend slope: $(round(r.trend,digits=4))")
    println()
    println("  ARIMA$(r.arima_order): AIC=$(round(r.arima_aic,digits=1))")
    println("  DLM log-lik: $(round(r.dlm_loglik,digits=1))")
    println()
    println("  Outbreak alarms:")
    println("    CUSUM:      $(r.cusum_alarms)")
    println("    Farrington: $(r.farrington_alarms)")
    println("    EWMA:       $(r.ewma_alarms)")
    println()
    if !isnan(r.cv_rmse)
        println("  Rolling CV RMSE: $(round(r.cv_rmse,digits=3))")
    end
    println("  $(r.forecast_h)-step forecast: $(round.(r.forecast_point,digits=2))")
    println("=" ^ 60)
end
