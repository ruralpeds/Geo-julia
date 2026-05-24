"""
    TimeSeriesHealth

Pure-Julia time-series forecasting and outbreak detection for healthcare.

# Exports
ARIMA: `arima_fit`, `ARIMAModel`, `auto_arima`, `acf`, `pacf`, `yule_walker`,
       `difference`, `undifference`, `arma_loglik`

State Space: `kalman_filter`, `LocalLevelModel`, `dlm_fit`, `dlm_predict`,
             `local_trend_fit`, `local_trend_predict`, `LocalTrendModel`

Outbreak: `cusum_detect`, `CUSUMResult`,
          `farrington_detect`, `FarringtonResult`,
          `poisson_ewma`, `PoissonEWMAResult`,
          `aberration_summary`

Forecast: `arima_forecast`, `ARIMAForecast`, `rolling_cv`, `RollingCVResult`,
          `bootstrap_forecast_pi`

Report: `ts_report`, `TimeSeriesReport`, `print_ts_report`
"""
module TimeSeriesHealth

using Statistics, LinearAlgebra, Random
using StateSpaceModels
using Distributions

include("arima.jl")
include("state_space.jl")
include("outbreak.jl")
include("forecast.jl")
include("report.jl")

export
    # ARIMA
    arima_fit, ARIMAModel, auto_arima,
    acf, pacf, yule_walker,
    difference, undifference, arma_loglik,
    # State space
    kalman_filter, LocalLevelModel, dlm_fit, dlm_predict,
    local_trend_fit, local_trend_predict, LocalTrendModel,
    # Outbreak
    cusum_detect, CUSUMResult,
    farrington_detect, FarringtonResult,
    poisson_ewma, PoissonEWMAResult,
    aberration_summary,
    # Forecast
    arima_forecast, ARIMAForecast,
    rolling_cv, RollingCVResult,
    bootstrap_forecast_pi,
    # Report
    ts_report, TimeSeriesReport, print_ts_report

end  # module
