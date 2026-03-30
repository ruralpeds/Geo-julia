#!/usr/bin/env julia
# scripts/ts_outbreak.jl
# Time-series forecasting and outbreak detection for ND healthcare data

using Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "packages", "TimeSeriesHealth", "src", "TimeSeriesHealth.jl"))
using .TimeSeriesHealth

println("=" ^ 65)
println("  Vol 9 — Time-Series Forecasting & Outbreak Detection")
println("  North Dakota Weekly Hospital Admissions")
println("=" ^ 65)

# ── Simulated ND weekly admissions ────────────────────────────────────────────

function make_nd_weekly_admissions(n=156; seed=5)
    rng = MersenneTwister(seed)
    # 3 years of weekly data (156 weeks)
    # Seasonal influenza: peaks in winter
    t     = collect(1.0:n)
    trend = 0.03 .* t
    seasonal = 20.0 .* sin.(2π .* t ./ 52 .+ π)  # winter peak
    baseline = 80.0 .+ trend .+ seasonal
    noise    = 5.0 .* randn(rng, n)
    y        = max.(baseline .+ noise, 0.0)

    # Inject two outbreaks
    for i in 30:36; y[i] += 35 + 5*rand(rng); end   # Week 30-36
    for i in 110:118; y[i] += 50 + 8*rand(rng); end # Week 110-118

    y
end

function make_poisson_counts(n=156; seed=9)
    rng = MersenneTwister(seed)
    μ_t = 12.0 .+ 4.0 .* sin.(2π .* collect(1:n) ./ 52)
    y   = [rand(rng) < 0.5 ? round(Int, μ_t[t] + randn(rng)) :
           round(Int, μ_t[t]) for t in 1:n]
    y   = Float64.(max.(y, 0))
    # Outbreak at week 135-143
    for t in 135:143; y[t] = round(Int, y[t] * 3.5); end
    y
end

y_adm   = make_nd_weekly_admissions()
y_count = make_poisson_counts()

println("\n► Admissions series: n=$(length(y_adm)), " *
        "mean=$(round(mean(y_adm),digits=1)), " *
        "range=[$(round(minimum(y_adm),digits=0)), $(round(maximum(y_adm),digits=0))]")

# ── Section 1: ACF / PACF ────────────────────────────────────────────────────

println("\n[1] ACF / PACF of Weekly Admissions")
ρ   = acf(y_adm, 10)
pa  = pacf(y_adm, 5)
println("  ACF lags 1–5: $(round.(ρ[2:6], digits=3))")
println("  PACF lags 1–5: $(round.(pa[1:5], digits=3))")
println("  Strong autocorrelation: $(any(abs.(ρ[2:6]) .> 0.3))")

# ── Section 2: ARIMA fitting ──────────────────────────────────────────────────

println("\n[2] ARIMA Model Selection (auto_arima)")
m_arima = auto_arima(y_adm; max_p=3, max_q=2, d=1, max_iter=50)
println("  Best model: ARIMA($(m_arima.p),$(m_arima.d),$(m_arima.q))  AIC=$(round(m_arima.aic,digits=1))")
println("  σ² = $(round(m_arima.σ²,digits=2))")

# ── Section 3: ARIMA forecasting ─────────────────────────────────────────────

println("\n[3] 8-Week Ahead Forecast")
fc = arima_forecast(m_arima, 8)
println("  Week  | Point | [80% PI]           | [95% PI]")
println("  " * "-"^58)
for h in 1:8
    println("  $(lpad(h,4))  | $(lpad(round(fc.point[h],digits=1),5)) | " *
            "[$(lpad(round(fc.lower_80[h],digits=1),6)), $(lpad(round(fc.upper_80[h],digits=1),6))] | " *
            "[$(lpad(round(fc.lower_95[h],digits=1),6)), $(lpad(round(fc.upper_95[h],digits=1),6))]")
end

# ── Section 4: DLM / Kalman filter ────────────────────────────────────────────

println("\n[4] Dynamic Linear Model (Kalman Filter)")
m_dlm = dlm_fit(y_adm; max_iter=30)
println("  σ²_ε = $(round(m_dlm.σ²_ε, digits=3))")
println("  σ²_η = $(round(m_dlm.σ²_η, digits=3))")
println("  Signal-to-noise q = $(round(m_dlm.σ²_η / m_dlm.σ²_ε, digits=4))")
println("  Log-likelihood = $(round(m_dlm.log_lik, digits=1))")

fc_dlm = dlm_predict(m_dlm, y_adm, 8)
println("  8-week DLM forecast: $(round.(fc_dlm.mean, digits=1))")

# ── Section 5: Local trend model ─────────────────────────────────────────────

println("\n[5] Local Trend Model")
m_lt  = local_trend_fit(y_adm; max_iter=25)
fc_lt = local_trend_predict(m_lt, 4)
println("  Current level: $(round(fc_lt.level, digits=1))")
println("  Current slope: $(round(fc_lt.slope, digits=3)) (admissions/week)")
println("  4-week forecast: $(round.(fc_lt.mean, digits=1))")

# ── Section 6: CUSUM outbreak detection ──────────────────────────────────────

println("\n[6] CUSUM Outbreak Detection")
y_base = y_count[1:52]
μ_base = mean(y_base)
σ_base = std(y_base)
cusum_r = cusum_detect(y_count; μ0=μ_base, σ0=σ_base, threshold=4.0, k=0.5)
println("  Baseline μ=$(round(μ_base,digits=1)), σ=$(round(σ_base,digits=2))")
println("  Alarms: $(sum(cusum_r.alarms)) at weeks: $(cusum_r.alarm_times[1:min(5,end)])")
println("  Max CUSUM statistic: $(round(maximum(cusum_r.statistics),digits=2))")

# ── Section 7: Farrington algorithm ──────────────────────────────────────────

println("\n[7] Farrington Surveillance Algorithm")
far_r = farrington_detect(y_count; n_years=2, period=52, w=2, alpha=0.05)
println("  Expected counts computed for weeks 105-156")
println("  Alarms: $(sum(far_r.alarms)) at weeks: $(far_r.alarm_times[1:min(5,end)])")
println("  Overdispersion φ̂ = $(round(far_r.overdispersion, digits=2))")
println("  Detection during outbreak (wk 135-143): $(any(far_r.alarms[133:145]))")

# ── Section 8: Poisson EWMA ──────────────────────────────────────────────────

println("\n[8] Poisson EWMA Surveillance")
ewma_r = poisson_ewma(y_count; λ=0.2, L=3.0)
println("  λ=0.2, L=3.0, baseline μ=$(round(ewma_r.baseline_μ,digits=1))")
println("  Alarms: $(sum(ewma_r.alarms)) at weeks: $(ewma_r.alarm_times[1:min(5,end)])")
println("  EWMA smoothness: std(EWMA)/std(raw) = $(round(std(ewma_r.statistics)/std(y_count),digits=3))")

# ── Section 9: Combined aberration summary ────────────────────────────────────

println("\n[9] Multi-method Outbreak Consensus")
summary_r = aberration_summary(y_count, cusum_r, far_r, ewma_r)
for i in eachindex(summary_r.method)
    println("  $(summary_r.method[i]): $(summary_r.n_alarms[i]) alarms")
end
println("  Combined alarms: $(summary_r.n_combined) ($(round(100*summary_r.alarm_rate,digits=1))% of weeks)")

# ── Section 10: Rolling cross-validation ─────────────────────────────────────

println("\n[10] Rolling Cross-Validation (1-week ahead)")
cv = rolling_cv(y_adm, 1; min_train=52, model_type=:arima, step=4)
println("  Folds: $(cv.n_folds)")
println("  RMSE:  $(round(cv.rmse, digits=2))")
println("  MAE:   $(round(cv.mae,  digits=2))")
println("  95% PI coverage: $(round(100*cv.coverage_95, digits=1))%")

# ── Section 11: Full time-series report ──────────────────────────────────────

println("\n[11] Full Time-Series Report")
report = ts_report(y_count;
                   series_name="ND-Weekly-ED-Admissions",
                   h_forecast=4, run_cv=false,
                   period=52, n_years_far=2)
print_ts_report(report)

println("\n✓ Time-series & outbreak detection analysis complete.")
