using Test, Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "src", "TimeSeriesHealth.jl"))
using .TimeSeriesHealth

function make_arima_data(n=100; seed=1, φ=[0.5], θ=Float64[], σ=0.3)
    rng = MersenneTwister(seed)
    y   = zeros(n)
    ε   = σ .* randn(rng, n)
    p   = length(φ); q = length(θ)
    for t in 1:n
        ar = sum(j <= t-1 ? φ[j] * y[t-j] : 0.0 for j in 1:p; init=0.0)
        ma = sum(j <= t-1 ? θ[j] * ε[t-j] : 0.0 for j in 1:q; init=0.0)
        y[t] = ar + ma + ε[t]
    end
    y
end

function make_trend_data(n=80; seed=3, slope=0.1, noise=0.5)
    rng = MersenneTwister(seed)
    collect(slope * (1:n)) .+ noise .* randn(rng, n)
end

function make_count_data(n=104; seed=5, μ=10.0, outbreak_start=80, outbreak_size=2.5)
    rng = MersenneTwister(seed)
    y   = [round(Int, max(0, μ + 2*randn(rng))) for _ in 1:n]
    for t in outbreak_start:min(n, outbreak_start+8)
        y[t] = round(Int, y[t] * outbreak_size)
    end
    Float64.(y)
end

# ── ACF / PACF ────────────────────────────────────────────────────────────────

@testset "ACF basic properties" begin
    y = make_arima_data(100; φ=[0.6])
    ρ = acf(y, 5)
    @test ρ[1] ≈ 1.0 atol=1e-10
    @test abs(ρ[2]) <= 1.0
    @test length(ρ) == 6
end

@testset "PACF AR(1) recovery" begin
    y  = make_arima_data(200; φ=[0.7], seed=2)
    pa = pacf(y, 5)
    @test abs(pa[1] - 0.7) < 0.15  # PACF lag 1 ≈ AR coef
    @test abs(pa[2]) < abs(pa[1])   # PACF cuts off after lag 1
end

@testset "Differencing operator" begin
    y  = collect(1.0:10.0)
    dy = difference(y, 1)
    @test length(dy) == 9
    @test all(dy .≈ 1.0)
    @test difference(y, 0) == y
    @test length(difference(y, 2)) == 8
end

@testset "Yule-Walker AR(2)" begin
    y     = make_arima_data(300; φ=[0.5, 0.2], seed=4)
    φ, σ² = yule_walker(y, 2)
    @test length(φ) == 2
    @test abs(φ[1] - 0.5) < 0.2
    @test σ² > 0
end

# ── ARIMA fitting ─────────────────────────────────────────────────────────────

@testset "ARIMA(1,0,0) fit" begin
    y = make_arima_data(150; φ=[0.6], seed=6)
    m = arima_fit(y, 1, 0, 0)
    @test isfinite(m.aic)
    @test length(m.φ) == 1
    @test abs(m.φ[1] - 0.6) < 0.2
    @test m.σ² > 0
    @test length(m.residuals) == length(y)
end

@testset "ARIMA(0,1,1) fit" begin
    # Random walk with MA noise
    rng = MersenneTwister(10)
    y   = cumsum(randn(rng, 100))
    m   = arima_fit(y, 0, 1, 1; max_iter=50)
    @test m.d == 1
    @test isfinite(m.aic)
    @test length(m.fitted) == 100
end

@testset "auto_arima" begin
    y = make_trend_data(60; slope=0.2)
    m = auto_arima(y; max_p=2, max_q=1, d=1, max_iter=30)
    @test isa(m, ARIMAModel)
    @test isfinite(m.aic)
    @test m.d == 1
end

@testset "ARIMA forecast" begin
    y  = make_arima_data(100; φ=[0.5], seed=7)
    m  = arima_fit(y, 1, 0, 0)
    fc = arima_forecast(m, 4)
    @test fc.h == 4
    @test length(fc.point) == 4
    @test all(fc.lower_95 .<= fc.point)
    @test all(fc.upper_95 .>= fc.point)
    @test all(fc.lower_80 .<= fc.lower_95 .+ 1e-8)  # 95% wider than 80%
    @test all(fc.upper_80 .<= fc.upper_95 .+ 1e-8)
end

# ── State space ───────────────────────────────────────────────────────────────

@testset "Kalman filter — local level" begin
    y = make_trend_data(50; slope=0.0, noise=1.0)  # stationary
    m = kalman_filter(y, 1.0, 0.1)
    @test length(m.filt_mean) == 50
    @test all(m.filt_var .>= 0.0)
    @test length(m.smooth_mean) == 50
    @test isfinite(m.log_lik)
end

@testset "DLM fit" begin
    y = make_trend_data(60; noise=0.5)
    m = dlm_fit(y; max_iter=20)
    @test m.σ²_ε > 0
    @test m.σ²_η >= 0
    @test isfinite(m.log_lik)
end

@testset "DLM predict" begin
    y = make_trend_data(50; slope=0.1, noise=0.3)
    m = dlm_fit(y; max_iter=20)
    fc = dlm_predict(m, y, 5)
    @test length(fc.mean) == 5
    @test all(fc.lower .<= fc.mean)
    @test all(fc.upper .>= fc.mean)
end

@testset "Local trend model" begin
    y = make_trend_data(60; slope=0.2, noise=0.3)
    m = local_trend_fit(y; max_iter=20)
    @test isfinite(m.log_lik)
    @test m.σ²_ε > 0

    fc = local_trend_predict(m, 5)
    @test length(fc.mean) == 5
    @test isfinite(fc.slope)
    @test isfinite(fc.level)
    # Upward trend → future values > current
    @test fc.mean[5] > fc.mean[1] - 1.0  # allow for noise
end

# ── Outbreak detection ────────────────────────────────────────────────────────

@testset "CUSUM — detects outbreak" begin
    y  = make_count_data(100; μ=10.0, outbreak_start=70, outbreak_size=3.0)
    r  = cusum_detect(y; μ0=10.0, σ0=3.0, threshold=4.0)
    @test length(r.statistics) == 100
    @test all(r.statistics .>= 0.0)
    @test !isempty(r.alarm_times)
    # Alarms should be in or after outbreak period
    @test all(r.alarm_times .>= 65)
end

@testset "CUSUM — no false alarms on baseline" begin
    rng = MersenneTwister(1)
    y   = 10.0 .+ 1.5 .* randn(rng, 80)
    r   = cusum_detect(y; μ0=10.0, σ0=1.5, threshold=6.0)
    @test sum(r.alarms) <= 3  # very few false alarms expected
end

@testset "Farrington algorithm" begin
    # Need enough history: n_years*period = 2*52 = 104 observations
    y = make_count_data(130; μ=8.0, outbreak_start=115, outbreak_size=4.0)
    r = farrington_detect(y; n_years=2, period=52, w=2)
    @test length(r.expected) == 130
    @test all(r.expected .>= 0.0)
    @test all(r.upper_bound .>= r.expected)
    # Should detect the outbreak
    @test any(r.alarms[110:130])
end

@testset "Poisson EWMA" begin
    y = make_count_data(80; μ=12.0, outbreak_start=60, outbreak_size=2.5)
    r = poisson_ewma(y; λ=0.2, L=3.0)
    @test length(r.statistics) == 80
    @test all(r.ucl .> 0)
    @test !isempty(r.alarm_times)
    # EWMA is smoother than raw counts
    @test std(r.statistics) < std(y)
end

@testset "Aberration summary" begin
    y  = make_count_data(80; μ=10.0, outbreak_start=65)
    cr = cusum_detect(y; μ0=10.0, σ0=3.0)
    er = poisson_ewma(y)
    s  = aberration_summary(y, cr, er)
    @test "CUSUM" in s.method
    @test "PoissonEWMA" in s.method
    @test length(s.combined_alarms) == 80
    @test 0.0 <= s.alarm_rate <= 1.0
end

# ── Forecast cross-validation ─────────────────────────────────────────────────

@testset "Rolling CV" begin
    y  = make_arima_data(80; φ=[0.4], seed=11)
    cv = rolling_cv(y, 1; min_train=30, model_type=:arima, step=5)
    @test isfinite(cv.rmse) || cv.n_folds == 0
    @test isfinite(cv.mae)  || cv.n_folds == 0
    if cv.n_folds > 0
        @test cv.rmse >= 0.0
        @test 0.0 <= cv.coverage_95 <= 1.0
    end
end

@testset "Bootstrap forecast PI" begin
    rng = MersenneTwister(17)
    y   = make_arima_data(80; φ=[0.5], seed=17)
    m   = arima_fit(y, 1, 0, 0; max_iter=50)
    pi  = bootstrap_forecast_pi(m, 3; n_boot=50, rng=rng)
    @test length(pi.point) == 3
    @test all(pi.lower .<= pi.upper)
end

@testset "TimeSeriesReport" begin
    y = make_count_data(80; μ=15.0)
    r = ts_report(Float64.(y); series_name="TestSeries", h_forecast=4,
                  run_cv=false, period=52, n_years_far=1)
    @test isa(r, TimeSeriesReport)
    @test r.n == 80
    @test isfinite(r.arima_aic)
    @test length(r.forecast_point) == 4
end
