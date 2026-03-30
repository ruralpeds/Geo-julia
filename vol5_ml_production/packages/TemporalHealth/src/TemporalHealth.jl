"""
    TemporalHealth

Time series analysis of healthcare outcomes and access metrics.
Chapter 37 — Julia Healthcare GIS Textbook, Vol 5.

Implements:
- STL decomposition (seasonal-trend via LOESS)
- ARIMA(p,d,q) with exact MLE via Kalman filter state-space representation
- Holt-Winters exponential smoothing (additive + multiplicative)
- Changepoint detection (PELT algorithm)
- Cross-correlation between spatial access and health outcomes
- Panel data handling (county × year)
"""
module TemporalHealth

using DataFrames, Dates, Statistics, LinearAlgebra, StatsBase

export HealthTimeSeries, from_dataframe
export stl_decompose, STLResult
export arima_fit, ARIMAModel, forecast
export holtwinters, HoltWintersModel
export detect_changepoints, PELTResult
export cross_correlation, lag_correlation
export panel_summary, panel_detrend
export seasonal_adjustment

include("types.jl")
include("stl.jl")
include("arima.jl")
include("changepoint.jl")
include("panel.jl")

end  # module TemporalHealth
