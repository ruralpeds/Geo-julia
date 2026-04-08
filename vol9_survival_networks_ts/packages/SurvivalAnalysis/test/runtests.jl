using Test, Statistics, Random

include(joinpath(@__DIR__, "..", "src", "SurvivalAnalysis.jl"))
using .SurvivalAnalysis

function make_surv_data(n=100; seed=1, competing=false)
    rng  = MersenneTwister(seed)
    t    = -log.(rand(rng, n)) .* 2.0    # Exponential(0.5) true times
    c    = -log.(rand(rng, n)) .* 4.0    # Exponential(0.25) censoring
    obs  = min.(t, c)
    if competing
        st = zeros(Int, n)
        for i in 1:n
            if t[i] <= c[i]
                st[i] = rand(rng) < 0.6 ? 1 : 2
            end
        end
    else
        st = Int.(t .<= c)
    end
    X = randn(rng, n, 2)
    (times=obs, status=st, X=X)
end

@testset "KaplanMeier — basic properties" begin
    d = make_surv_data(200)
    km = kaplan_meier(d.times, d.status)
    @test km.survival[1] <= 1.0
    @test km.survival[end] >= 0.0
    @test issorted(km.survival, rev=true) || issorted(km.survival)
    @test all(km.survival .>= 0.0)
    @test all(km.survival .<= 1.0)
    @test isfinite(km.median_survival)
    @test km.restricted_mean >= 0.0
end

@testset "KaplanMeier — confidence intervals" begin
    d = make_surv_data(150)
    km = kaplan_meier(d.times, d.status)
    @test all(km.lower_ci .<= km.survival .+ 1e-10)
    @test all(km.upper_ci .>= km.survival .- 1e-10)
    @test all(0.0 .<= km.lower_ci .<= 1.0)
    @test all(0.0 .<= km.upper_ci .<= 1.0)
end

@testset "KaplanMeier — km_predict" begin
    d = make_surv_data(100)
    km = kaplan_meier(d.times, d.status)
    @test km_predict(km, 0.0)  == 1.0
    @test km_predict(km, -1.0) == 1.0
    @test km_predict(km, km.times[end]) ≈ km.survival[end]
end

@testset "KaplanMeier — complete data" begin
    # All events (no censoring), exponential true rate λ=1 → median ≈ log(2)
    rng = MersenneTwister(42)
    t   = -log.(rand(rng, 500))
    st  = ones(Int, 500)
    km  = kaplan_meier(t, st)
    @test abs(km.median_survival - log(2)) < 0.1
end

@testset "Nelson-Aalen" begin
    d  = make_surv_data(100)
    na = nelson_aalen(d.times, d.status)
    @test all(na.cum_hazard .>= 0.0)
    @test issorted(na.cum_hazard)
    @test all(na.variance .>= 0.0)
    @test length(na.times) == length(na.cum_hazard)
    @test all(na.lower_ci .<= na.upper_ci)
end

@testset "Log-rank test — two groups" begin
    rng = MersenneTwister(7)
    n   = 100
    t1  = -log.(rand(rng, n)) .* 1.0   # λ=1
    t2  = -log.(rand(rng, n)) .* 0.5   # λ=2 (worse survival)
    c   = ones(Int, 2n)
    t   = vcat(t1, t2)
    g   = vcat(fill("A", n), fill("B", n))
    lr  = logrank_test(t, c, g)
    @test lr.statistic >= 0.0
    @test 0.0 <= lr.p_value <= 1.0
    @test lr.df == 1
    @test length(lr.observed) == 2
    # Groups with different rates should have p < 0.05
    @test lr.p_value < 0.05
end

@testset "Log-rank test — Wilcoxon" begin
    rng = MersenneTwister(9)
    t   = -log.(rand(rng, 80)) .* 1.0
    st  = ones(Int, 80)
    g   = repeat(["A","B"], 40)
    wl  = logrank_test(t, st, g; test_type=:wilcoxon)
    @test wl.statistic >= 0.0
    @test 0.0 <= wl.p_value <= 1.0
end

@testset "Cox PH — coefficient recovery" begin
    rng  = MersenneTwister(3)
    n    = 200
    β_true = [0.5, -0.3]
    X    = randn(rng, n, 2)
    η    = X * β_true
    lam  = exp.(η)
    t    = -log.(rand(rng, n)) ./ lam
    c    = rand(rng, n) .* 3.0
    obs  = min.(t, c); st = Int.(t .<= c)
    m    = cox_fit(obs, st, X)
    @test m.converged
    @test abs(m.β[1] - β_true[1]) < 0.3
    @test abs(m.β[2] - β_true[2]) < 0.3
    @test all(m.se .> 0.0)
    @test all(0.0 .<= m.p_values .<= 1.0)
end

@testset "Cox PH — concordance" begin
    d = make_surv_data(150)
    m = cox_fit(d.times, d.status, d.X)
    @test 0.0 <= m.concordance <= 1.0
end

@testset "Cox PH — predict" begin
    d  = make_surv_data(100)
    m  = cox_fit(d.times, d.status, d.X)
    r  = cox_predict(m, d.X[1:5,:])
    @test length(r.hazard_ratio) == 5
    @test all(r.hazard_ratio .> 0.0)
    @test size(r.survival, 1) == 5
    @test all(0.0 .<= r.survival .<= 1.0)
end

@testset "Cox PH — summary" begin
    d = make_surv_data(80)
    m = cox_fit(d.times, d.status, d.X; feature_names=["x1","x2"])
    s = cox_summary(m)
    @test :feature in keys(s)
    @test :p_value in keys(s)
    @test length(s.feature) == 2
end

@testset "Parametric AFT — Weibull" begin
    rng = MersenneTwister(5)
    n   = 150
    X   = randn(rng, n, 2)
    μ   = 2.0 .+ X * [0.3, -0.2]
    t   = exp.(μ .+ 0.5 .* randn(rng, n))   # log-normal approx Weibull
    c   = rand(rng, n) .* 20.0
    obs = min.(t, c); st = Int.(t .<= c)
    pm  = parametric_fit(obs, st, X; dist=:weibull)
    @test pm.converged
    @test isfinite(pm.log_lik)
    @test isfinite(pm.aic)
    @test length(pm.β) == 3
end

@testset "Parametric AFT — predict" begin
    d  = make_surv_data(100)
    pm = parametric_fit(d.times, d.status, d.X; dist=:weibull)
    q  = parametric_predict(pm, d.X[1:5,:])
    @test :q50 in keys(q)
    @test all(q[:q50] .> 0.0)
    sv = parametric_survival(pm, d.X[1:5,:], 1.0)
    @test all(0.0 .<= sv .<= 1.0)
end

@testset "Parametric AFT — Exponential and Log-logistic" begin
    d = make_surv_data(100)
    m_exp = parametric_fit(d.times, d.status, d.X; dist=:exponential)
    m_ll  = parametric_fit(d.times, d.status, d.X; dist=:loglogistic)
    @test isfinite(m_exp.aic)
    @test isfinite(m_ll.aic)
end

@testset "Competing risks — CIF" begin
    d   = make_surv_data(120; competing=true)
    cif = cumulative_incidence(d.times, d.status)
    @test 1 in cif.cause_labels
    @test 2 in cif.cause_labels
    # CIF is non-decreasing
    cif1 = cif.cif[1]
    @test issorted(cif1)
    @test all(0.0 .<= cif1 .<= 1.0)
    # Sum of CIFs <= 1
    n_t = length(cif.times)
    if !isempty(cif.cif[1]) && !isempty(cif.cif[2])
        n_min = min(length(cif.cif[1]), length(cif.cif[2]))
        @test all(cif.cif[1][1:n_min] .+ cif.cif[2][1:n_min] .<= 1.0 + 1e-8)
    end
end

@testset "Competing risks — cif_at" begin
    d   = make_surv_data(100; competing=true)
    cif = cumulative_incidence(d.times, d.status)
    @test cif_at(cif, 1, 0.0) == 0.0
    v   = cif_at(cif, 1, maximum(d.times))
    @test 0.0 <= v <= 1.0
end

@testset "Fine-Gray model" begin
    d   = make_surv_data(120; competing=true)
    fg  = fine_gray_fit(d.times, d.status, d.X; cause=1)
    @test length(fg.β) == 2
    @test all(isfinite.(fg.β))
    @test all(fg.se .>= 0.0)
    @test all(0.0 .<= fg.p_values .<= 1.0)
end

@testset "Survival report" begin
    d = make_surv_data(100)
    r = survival_report(d.times, d.status;
                         X=d.X, feature_names=["age","pov"],
                         groups=repeat(["A","B"], 50))
    @test isa(r, SurvivalReport)
    @test r.n_total == 100
    @test r.n_events >= 0
    @test 0.0 <= r.pct_censored <= 100.0
    @test !isnothing(r.km_result)
    @test !isnothing(r.cox_model)
    @test !isnothing(r.log_rank)
end
