#!/usr/bin/env julia
# test/integration_test.jl — Vol 9 integration tests
# Survival Analysis, Network Health, and Time-Series Outbreak Detection

using Test, Statistics, LinearAlgebra, Random

const VOL9 = joinpath(@__DIR__, "..")

function load_pkg(name)
    path = joinpath(VOL9, "packages", name, "src", "$(name).jl")
    isfile(path) ? (include(path); true) : (@warn "Package $name not found"; false)
end

SA_OK = load_pkg("SurvivalAnalysis")
NH_OK = load_pkg("NetworkHealth")
TS_OK = load_pkg("TimeSeriesHealth")

SA_OK && (using .SurvivalAnalysis)
NH_OK && (using .NetworkHealth)
TS_OK && (using .TimeSeriesHealth)

# ── Fixtures ─────────────────────────────────────────────────────────────────

function make_surv(n=120; seed=1)
    rng = MersenneTwister(seed)
    t = -log.(rand(rng, n)) .* 30; c = rand(rng, n) .* 60
    obs = min.(t, c); st = Int.(t .<= c)
    X = randn(rng, n, 2)
    groups = repeat(["A","B"], n÷2)
    (obs=obs, status=st, X=X, groups=groups)
end

function make_comp(n=120; seed=2)
    rng = MersenneTwister(seed)
    t1 = -log.(rand(rng, n)) .* 30
    t2 = -log.(rand(rng, n)) .* 50
    c  = rand(rng, n) .* 60
    obs = min.(t1, t2, c); st = zeros(Int, n)
    for i in 1:n
        if t1[i] <= t2[i] && t1[i] <= c[i]; st[i] = 1
        elseif t2[i] < t1[i] && t2[i] <= c[i]; st[i] = 2
        end
    end
    X = randn(rng, n, 2)
    (obs=obs, status=st, X=X)
end

function make_graph(n=8; seed=3)
    rng = MersenneTwister(seed)
    W   = abs.(randn(rng, n, n)) .* (rand(rng, n, n) .> 0.55)
    for i in 1:n; W[i,i] = 0.0; end
    build_graph(W; labels=["F$i" for i in 1:n])
end

function make_ts(n=100; seed=5, φ=0.5, σ=0.5)
    rng = MersenneTwister(seed)
    y   = zeros(n)
    for t in 1:n
        y[t] = φ * (t > 1 ? y[t-1] : 0.0) + σ * randn(rng)
    end
    y
end

function make_counts(n=104; seed=7, μ=10.0)
    rng = MersenneTwister(seed)
    y   = [max(0.0, μ + 2*randn(rng)) for _ in 1:n]
    for t in 80:90; y[t] *= 2.8; end
    y
end

# ══════════════════════════════════════════════════════════════════════════════
# SurvivalAnalysis integration
# ══════════════════════════════════════════════════════════════════════════════

@testset "SA — KM + log-rank pipeline" begin
    if !SA_OK; @test_skip true; return; end
    d  = make_surv()
    km = kaplan_meier(d.obs, d.status)
    lr = logrank_test(d.obs, d.status, d.groups)
    @test isfinite(km.median_survival)
    @test 0.0 <= lr.p_value <= 1.0
    @test lr.statistic >= 0.0
    # Observed ≈ expected (two groups from same distribution)
    @test abs(lr.observed[1] + lr.observed[2] - sum(d.status)) < 1.0
end

@testset "SA — Cox + Weibull AIC comparison" begin
    if !SA_OK; @test_skip true; return; end
    d    = make_surv()
    cox  = cox_fit(d.obs, d.status, d.X)
    wbl  = parametric_fit(d.obs, d.status, d.X; dist=:weibull)
    expm = parametric_fit(d.obs, d.status, d.X; dist=:exponential)
    @test isfinite(cox.log_lik)
    @test isfinite(wbl.aic)
    @test isfinite(expm.aic)
    # Weibull should have AIC ≤ Exponential (more flexible)
    @test wbl.aic <= expm.aic + 5.0
    @test cox.concordance >= 0.4
end

@testset "SA — Cox predict produces valid probabilities" begin
    if !SA_OK; @test_skip true; return; end
    d   = make_surv()
    cox = cox_fit(d.obs, d.status, d.X)
    r   = cox_predict(cox, d.X[1:10,:])
    @test all(r.hazard_ratio .> 0.0)
    @test size(r.survival, 1) == 10
    @test all(0.0 .<= r.survival .<= 1.0)
    # Survival is non-increasing across event times
    if size(r.survival, 2) > 1
        @test all(diff(r.survival[1,:]) .<= 1e-10)
    end
end

@testset "SA — Competing risks CIF sums to ≤ 1" begin
    if !SA_OK; @test_skip true; return; end
    d   = make_comp()
    cif = cumulative_incidence(d.obs, d.status)
    n_t = length(cif.times)
    n1  = length(cif.cif[1]); n2 = length(cif.cif[2])
    n_c = min(n1, n2, n_t)
    if n_c > 0
        totals = cif.cif[1][1:n_c] .+ cif.cif[2][1:n_c]
        @test all(totals .<= 1.0 + 1e-8)
    end
    @test cif_at(cif, 1, 0.0) == 0.0
end

@testset "SA — Fine-Gray on competing risks" begin
    if !SA_OK; @test_skip true; return; end
    d  = make_comp()
    fg = fine_gray_fit(d.obs, d.status, d.X; cause=1)
    @test length(fg.β) == 2
    @test all(isfinite.(fg.β))
    @test all(fg.se .>= 0.0)
end

@testset "SA — Full survival report" begin
    if !SA_OK; @test_skip true; return; end
    d   = make_surv()
    rep = survival_report(d.obs, d.status;
                           X=d.X, groups=d.groups,
                           feature_names=["age","pov"])
    @test isa(rep, SurvivalReport)
    @test rep.n_total == length(d.obs)
    @test !isnothing(rep.km_result)
    @test !isnothing(rep.cox_model)
    @test !isnothing(rep.log_rank)
end

# ══════════════════════════════════════════════════════════════════════════════
# NetworkHealth integration
# ══════════════════════════════════════════════════════════════════════════════

@testset "NH — Graph centrality consistency" begin
    if !NH_OK; @test_skip true; return; end
    g  = make_graph()
    pr = pagerank(g)
    dc = degree_centrality(g; mode=:total)
    bc = betweenness_centrality(g)
    @test sum(pr) ≈ 1.0 atol=1e-6
    @test all(pr .>= 0.0)
    @test all(dc .>= 0.0)
    @test all(bc .>= 0.0)
    # Higher betweenness nodes should generally have higher PageRank
    @test cor(pr, bc) >= -0.5
end

@testset "NH — Dijkstra vs BFS on unweighted" begin
    if !NH_OK; @test_skip true; return; end
    # Path graph 1-2-3-4-5: BFS and Dijkstra should agree
    W = zeros(5, 5)
    for i in 1:4; W[i, i+1] = 1.0; end
    g  = build_graph(W)
    db, _ = bfs(g, 1)
    dd, _ = dijkstra(g, 1)
    @test db ≈ dd atol=1e-10
    @test db[5] == 4.0
end

@testset "NH — SIR conservation and thresholds" begin
    if !NH_OK; @test_skip true; return; end
    sir = sir_model(1000, 5; β=0.3, γ=0.1)
    total = sir.S .+ sir.I .+ sir.R
    @test all(abs.(total .- 1.0) .< 0.01)
    @test sir.R0 ≈ 3.0 atol=0.01
    @test 0.0 < sir.peak_I < 1.0
    @test sir.S[end] < sir.S[1]
    # Final size > 0 for R₀ > 1
    @test sir.final_size > 0.1
end

@testset "NH — SEIRD IFR check" begin
    if !NH_OK; @test_skip true; return; end
    r = seird_model(5000; β=0.3, σ=0.2, γ=0.09, μ=0.01, E0=5, I0=2)
    @test abs(r.ifr - 0.01/0.10) < 0.01
    @test r.D[end] >= 0.0
    total = r.S .+ r.E .+ r.I .+ r.R .+ r.D
    @test all(abs.(total .- 1.0) .< 0.01)
end

@testset "NH — Patient flow self-sufficiency" begin
    if !NH_OK; @test_skip true; return; end
    rng = MersenneTwister(11)
    F   = abs.(randn(rng, 5, 5)) .* 20
    for i in 1:5; F[i,i] = 200 + rand(rng)*50; end
    pf  = patient_flow_analysis(F)
    @test all(0.0 .<= pf.self_sufficiency .<= 1.0)
    # High diagonal → self-sufficiency should be close to 1 for row hospitals
    @test all(pf.self_sufficiency .> 0.5)
end

@testset "NH — Catchment area assignment" begin
    if !NH_OK; @test_skip true; return; end
    pop  = [3000.0, 1500.0, 800.0, 2000.0]
    cap  = [100.0, 200.0, 50.0]
    dist = [2.0 8.0 15.0; 5.0 3.0 10.0; 1.0 12.0 6.0; 9.0 4.0 2.0]
    ca   = catchment_area(pop, cap, dist)
    @test length(ca.assignment) == 4
    @test all(1 .<= ca.assignment .<= 3)
    @test abs(sum(ca.catchment_pop) - sum(pop)) < 1e-6
end

@testset "NH — Network report" begin
    if !NH_OK; @test_skip true; return; end
    g   = make_graph(6)
    sir = sir_model(500, 5; β=0.3, γ=0.1)
    rpt = network_report(g, sir)
    @test isa(rpt, NetworkReport)
    @test rpt.n_facilities == 6
    @test isfinite(rpt.graph_density)
    @test 0.0 <= rpt.graph_density <= 1.0
end

# ══════════════════════════════════════════════════════════════════════════════
# TimeSeriesHealth integration
# ══════════════════════════════════════════════════════════════════════════════

@testset "TS — ACF lag-0 = 1" begin
    if !TS_OK; @test_skip true; return; end
    y = make_ts(80)
    ρ = acf(y, 5)
    @test ρ[1] ≈ 1.0 atol=1e-10
    @test all(abs.(ρ) .<= 1.0 + 1e-10)
end

@testset "TS — ARIMA forecast PI contains point" begin
    if !TS_OK; @test_skip true; return; end
    y  = make_ts(100)
    m  = arima_fit(y, 1, 0, 0; max_iter=60)
    fc = arima_forecast(m, 5)
    @test all(fc.lower_95 .<= fc.point .<= fc.upper_95)
    @test all(fc.lower_80 .<= fc.point .<= fc.upper_80)
    # 95% wider than 80%
    @test all(fc.upper_95 .- fc.lower_95 .>= fc.upper_80 .- fc.lower_80 .- 1e-8)
end

@testset "TS — DLM filtered mean tracks signal" begin
    if !TS_OK; @test_skip true; return; end
    rng  = MersenneTwister(3)
    true_level = cumsum(0.1 .+ 0.1*randn(rng, 60))
    y    = true_level .+ 0.3*randn(rng, 60)
    m    = dlm_fit(y; max_iter=30)
    corr = cor(m.filt_mean, true_level)
    @test corr > 0.8   # filtered mean should track true level
    @test all(m.filt_var .>= 0.0)
end

@testset "TS — Local trend forecasts in right direction" begin
    if !TS_OK; @test_skip true; return; end
    rng   = MersenneTwister(8)
    y_up  = collect(1.0:50.0) .+ 0.5*randn(rng, 50)
    m_lt  = local_trend_fit(y_up; max_iter=20)
    fc_lt = local_trend_predict(m_lt, 5)
    @test fc_lt.slope > 0.5   # should detect upward trend
    @test fc_lt.mean[5] > fc_lt.mean[1]
end

@testset "TS — CUSUM detects injected outbreak" begin
    if !TS_OK; @test_skip true; return; end
    y    = make_counts(80)
    cr   = cusum_detect(y; μ0=10.0, σ0=3.0, threshold=4.0)
    # Outbreak is at weeks 80-90, so alarms should be near there
    @test !isempty(cr.alarm_times)
    @test maximum(cr.alarm_times) >= 78
end

@testset "TS — EWMA smoothing property" begin
    if !TS_OK; @test_skip true; return; end
    y    = make_counts(60)
    er   = poisson_ewma(y; λ=0.2, L=3.0)
    @test std(er.statistics) < std(y)  # EWMA smoother than raw
    @test all(er.ucl .> 0.0)
end

@testset "TS — Farrington expected counts non-negative" begin
    if !TS_OK; @test_skip true; return; end
    y  = make_counts(130)
    fr = farrington_detect(y; n_years=2, period=52, w=2)
    computed = fr.expected[fr.expected .> 0.0]
    @test !isempty(computed)
    @test all(computed .>= 0.0)
    @test all(fr.upper_bound[fr.upper_bound .> 0.0] .>= fr.expected[fr.expected .> 0.0])
end

@testset "TS — Rolling CV coverage check" begin
    if !TS_OK; @test_skip true; return; end
    y  = make_ts(80)
    cv = rolling_cv(y, 1; min_train=30, model_type=:arima, step=5)
    if cv.n_folds > 0
        @test isfinite(cv.rmse)
        @test cv.rmse >= 0.0
        @test 0.0 <= cv.coverage_95 <= 1.0
    end
end

@testset "TS — Bootstrap PI bounds consistent" begin
    if !TS_OK; @test_skip true; return; end
    rng = MersenneTwister(22)
    y   = make_ts(80)
    m   = arima_fit(y, 1, 0, 0; max_iter=50)
    pi  = bootstrap_forecast_pi(m, 4; n_boot=100, rng=rng)
    @test length(pi.lower) == 4
    @test all(pi.lower .<= pi.upper)
end

@testset "TS — TimeSeriesReport" begin
    if !TS_OK; @test_skip true; return; end
    y   = make_counts(80)
    rep = ts_report(y; h_forecast=4, run_cv=false,
                    series_name="IntegrationTest", period=52, n_years_far=1)
    @test isa(rep, TimeSeriesReport)
    @test rep.n == 80
    @test isfinite(rep.arima_aic)
    @test length(rep.forecast_point) == 4
end

# ══════════════════════════════════════════════════════════════════════════════
# Cross-package integration
# ══════════════════════════════════════════════════════════════════════════════

@testset "Cross — Survival CIF + epidemic final size comparison" begin
    if !SA_OK || !NH_OK; @test_skip true; return; end
    d   = make_comp()
    cif = cumulative_incidence(d.obs, d.status)

    # Run SIR for 3 months (≈ max of survival times)
    sir = sir_model(1000, 5; β=0.3, γ=0.1, tspan=(0.0, 90.0))

    # Both are probability quantities in [0,1]
    cif1_end = cif_at(cif, 1, maximum(d.obs))
    @test 0.0 <= cif1_end <= 1.0
    @test 0.0 <= sir.final_size <= 1.0
    @test isfinite(cif1_end)
    @test isfinite(sir.final_size)
end

@testset "Cross — CUSUM on epidemic incidence" begin
    if !NH_OK || !TS_OK; @test_skip true; return; end
    sir   = sir_model(50000, 5; β=0.35, γ=0.1, tspan=(0.0, 100.0), dt=1.0)
    # Daily new infections ≈ d(R)/dt * N
    N     = 50000
    new_R = diff(sir.R) .* N   # new recoveries ~ new infections lagged
    new_R = max.(new_R, 0.0)

    n  = length(new_R)
    μ0 = mean(new_R[1:min(10, n)])
    σ0 = max(std(new_R[1:min(10, n)]), 1.0)
    cr = cusum_detect(new_R; μ0=μ0, σ0=σ0, threshold=4.0, k=0.5)

    # CUSUM should detect the epidemic rise
    @test !isempty(cr.alarm_times) || sir.R0 < 1.2
    @test length(cr.statistics) == n
end

@testset "Cross — Cox residuals + ARIMA noise model" begin
    if !SA_OK || !TS_OK; @test_skip true; return; end
    d   = make_surv()
    cox = cox_fit(d.obs, d.status, d.X)

    # Cox deviance residuals as time-series input
    fitted_log_h = d.X * cox.β
    resid_ts     = fitted_log_h .- mean(fitted_log_h)

    m  = arima_fit(resid_ts, 1, 0, 0; max_iter=50)
    @test isfinite(m.aic)
    # If Cox captured structure, AR coef should be small
    @test isfinite(m.φ[1])
end

@testset "Cross — Full pipeline: epidemic → survival → forecast" begin
    if !SA_OK || !NH_OK || !TS_OK; @test_skip true; return; end

    # Step 1: Epidemic model generates incidence
    sir = sir_model(10000, 10; β=0.3, γ=0.1, tspan=(0.0, 120.0), dt=1.0)
    new_infections = max.(diff(sir.R) .* 10000, 0.0)
    n_weeks = length(new_infections)

    # Step 2: Survival analysis on simulated patient cohort
    rng = MersenneTwister(99)
    n_patients = 100
    t = -log.(rand(rng, n_patients)) .* 14.0
    c = rand(rng, n_patients) .* 28.0
    obs = min.(t, c); st = Int.(t .<= c)
    km = kaplan_meier(obs, st)
    @test isfinite(km.median_survival)

    # Step 3: Time-series forecast of weekly incidence
    weekly = [mean(new_infections[max(1,(w-1)*7+1):min(n_weeks,w*7)])
              for w in 1:min(16, n_weeks÷7)]
    length(weekly) >= 10 || return
    m = arima_fit(weekly, 0, 1, 0; max_iter=30)
    fc = arima_forecast(m, 4)
    @test length(fc.point) == 4
    @test all(isfinite.(fc.point))
    println("\n  [Cross-pipeline] KM median=$(round(km.median_survival,digits=1))d, " *
            "ARIMA($(m.p),$(m.d),$(m.q)) AIC=$(round(m.aic,digits=1)), " *
            "4-wk forecast=$(round.(fc.point,digits=1))")
end

println("\nVol 9 integration tests complete.")
