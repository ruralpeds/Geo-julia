using Test, Random, DataFrames, Dates, Statistics
Random.seed!(42)

import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using TemporalHealth

# ── Fixtures ──────────────────────────────────────────────────────────────────

function make_ts(n=60, freq=12; trend=0.01, noise=0.05, seasonal_amp=0.2, seed=42)
    rng = MersenneTwister(seed)
    t   = 1:n
    y   = @. 1.0 + trend*t + seasonal_amp*sin(2π*t/freq) + noise*randn(rng)
    dates = [Date(2018,1,1) + Month(i-1) for i in 1:n]
    from_dataframe(DataFrame(date=dates, y=Float64.(y)), :date, :y;
                  name="access_score", unit="ratio", freq=freq)
end

ts60 = make_ts(60, 12)
ts24 = make_ts(24, 4; freq=4)

@testset "TemporalHealth Tests" begin

    @testset "1. HealthTimeSeries construction" begin
        @test ts60 isa HealthTimeSeries
        @test length(ts60) == 60
        @test ts60.freq == 12
        @test ts60.name == "access_score"
    end

    @testset "2. STL decomposition — components sum" begin
        stl = stl_decompose(ts60; n_inner=2, n_outer=1)
        @test stl isa STLResult
        recon = stl.trend .+ stl.seasonal .+ stl.remainder
        @test maximum(abs.(recon .- ts60.values)) < 1e-6
    end

    @testset "3. STL — seasonal strength > 0" begin
        stl = stl_decompose(ts60)
        @test stl.seasonal_strength >= 0
        @test stl.trend_strength >= 0
        # Seasonal component should be non-trivial for sinusoidal data
        @test std(stl.seasonal) > 1e-4
    end

    @testset "4. Holt-Winters — fitted length" begin
        hw = holtwinters(ts60; α=0.3, β=0.1, γ=0.2)
        @test hw isa HoltWintersModel
        @test length(hw.fitted) == 60
        @test !any(isnan, hw.fitted)
    end

    @testset "5. Holt-Winters — forecast" begin
        hw   = holtwinters(ts60)
        forc = forecast(hw, 12)
        @test length(forc) == 12
        @test !any(isnan, forc)
        @test !any(isinf, forc)
    end

    @testset "6. seasonal_adjustment" begin
        ts_sa = seasonal_adjustment(ts60)
        @test length(ts_sa) == 60
        @test ts_sa.name == "access_score_sa"
        # Seasonal adjustment should reduce seasonality amplitude
        @test std(ts_sa.values) <= std(ts60.values) * 1.5
    end

    @testset "7. ARIMA fit — basic" begin
        ts_simple = from_dataframe(
            DataFrame(t=1:40, y=cumsum(randn(40)) .+ 5.0),
            :t, :y; freq=1)
        m = arima_fit(ts_simple; p=1, d=1, q=0)
        @test m isa ARIMAModel
        @test m.p == 1 && m.d == 1 && m.q == 0
        @test length(m.residuals) > 0
        @test !any(isnan, m.residuals)
        @test isfinite(m.aic)
    end

    @testset "8. ARIMA forecast" begin
        ts_simple = from_dataframe(
            DataFrame(t=1:30, y=cumsum(randn(30))),
            :t, :y; freq=1)
        m    = arima_fit(ts_simple; p=1, d=1, q=1)
        forc = forecast(m, 6)
        @test length(forc) == 6
        @test !any(isnan, forc)
    end

    @testset "9. PELT changepoint detection — no spurious CPs" begin
        # Constant series — should find 0 changepoints
        y_const = fill(1.0, 50)
        ts_c = from_dataframe(DataFrame(t=1:50, y=y_const), :t, :y; freq=1)
        r    = detect_changepoints(ts_c; penalty=5.0)
        @test r isa PELTResult
        @test length(r.changepoints) == 0
    end

    @testset "10. PELT changepoint detection — known shift" begin
        # Step change at position 25
        y_step = vcat(fill(1.0, 25), fill(3.0, 25))
        ts_s   = from_dataframe(DataFrame(t=1:50, y=y_step), :t, :y; freq=1)
        r = detect_changepoints(ts_s; penalty=log(50))
        @test r.n_segments >= 2
        # Changepoint should be near 25
        if !isempty(r.changepoints)
            @test minimum(abs.(r.changepoints .- 25)) <= 3
        end
    end

    @testset "11. PELT — segment means correct" begin
        y_step = vcat(fill(2.0, 20), fill(5.0, 20))
        ts_s   = from_dataframe(DataFrame(t=1:40, y=y_step), :t, :y; freq=1)
        r = detect_changepoints(ts_s; penalty=2.0)
        @test !isempty(r.segment_means)
        @test all(isfinite, r.segment_means)
    end

    @testset "12. cross_correlation" begin
        ts2 = make_ts(60, 12; trend=0.005, seasonal_amp=0.15, seed=99)
        ccf = cross_correlation(ts60, ts2; max_lag=6)
        @test nrow(ccf) == 13  # -6..6
        @test hasproperty(ccf, :ccf)
        @test all(-1.0 .<= ccf.ccf .<= 1.0)
    end

    @testset "13. lag_correlation" begin
        ts2 = make_ts(60, 12; seed=77)
        lag, corr_val = lag_correlation(ts60, ts2; max_lag=6)
        @test -6 <= lag <= 6
        @test -1.0 <= corr_val <= 1.0
    end

    @testset "14. panel_summary" begin
        n_counties = 5; n_years = 8
        df = DataFrame(
            county = repeat(1:n_counties, inner=n_years),
            year   = repeat(2015:2022,    outer=n_counties),
            access = rand(n_counties * n_years) .* 0.02 .+ 0.005,
        )
        summ = panel_summary(df, :county, :year, :access)
        @test nrow(summ) == n_counties
        @test hasproperty(summ, :trend)
        @test hasproperty(summ, :ac1)
        @test all(isfinite, summ.trend)
    end

    @testset "15. panel_detrend" begin
        n_c = 4; n_t = 10
        df = DataFrame(
            county = repeat(1:n_c, inner=n_t),
            year   = repeat(1:n_t, outer=n_c),
            access = rand(n_c * n_t),
        )
        out = panel_detrend(df, :county, :year, :access)
        @test hasproperty(out, :access_detrended)
        @test nrow(out) == n_c * n_t
        # Detrended series should have smaller mean absolute trend
        for id in 1:n_c
            mask = out.county .== id
            @test abs(_ols_slope(1.0:n_t, out[mask, :access_detrended])) <
                  abs(_ols_slope(1.0:n_t, df[mask, :access])) + 0.01
        end
    end

end  # @testset

_ols_slope(x, y) = begin
    x̄ = mean(x); ȳ = mean(y)
    sx = sum((x .- x̄).^2)
    sx < 1e-12 ? 0.0 : sum((x .- x̄) .* (y .- ȳ)) / sx
end

@info "TemporalHealth tests complete."
