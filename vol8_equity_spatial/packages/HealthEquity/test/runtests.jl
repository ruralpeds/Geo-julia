#!/usr/bin/env julia
# test/runtests.jl — HealthEquity.jl unit tests

using Test, Random, Statistics
using HealthEquity

Random.seed!(42)

# ── Fixtures ──────────────────────────────────────────────────────────────────
n = 200
rng = MersenneTwister(42)
y     = rand(rng, [0, 1], n)
probs = clamp.(0.3 .+ 0.4 .* Float64.(y) .+ 0.15*randn(rng, n), 0.01, 0.99)
ŷ     = Int.(probs .>= 0.5)
groups = repeat(["rural", "urban"], n÷2)
X_feat = randn(rng, n, 4)
ses    = randn(rng, n)

@testset "HealthEquity.jl" begin

    @testset "demographic_parity — returns DataFrame" begin
        dp = demographic_parity(ŷ, groups)
        @test nrow(dp) >= 1
        @test hasproperty(dp, :dp_diff)
        @test all(dp.dp_diff .>= 0)
    end

    @testset "equalized_odds — TPR/FPR in [0,1]" begin
        eo = equalized_odds(ŷ, y, groups)
        @test nrow(eo) == 2
        @test all(0 .<= eo.tpr .<= 1)
        @test all(0 .<= eo.fpr .<= 1)
    end

    @testset "calibration_gap — bins correct" begin
        cg = calibration_gap(probs, y, groups; n_bins=5)
        @test nrow(cg) == 5
        @test hasproperty(cg, :cal_gap)
    end

    @testset "gini_coefficient — 0 for equal, 1 for maximal" begin
        @test gini_coefficient(ones(10)) ≈ 0.0 atol=1e-10
        @test gini_coefficient([1.0, 0.0, 0.0, 0.0]) > 0.5
        @test 0 <= gini_coefficient(rand(20)) <= 1
    end

    @testset "theil_index — non-negative, 0 for equal" begin
        @test theil_index(ones(10)) ≈ 0.0 atol=1e-10
        @test theil_index(rand(rng, 20) .+ 0.1) >= 0
    end

    @testset "concentration_index — in [-1, 1]" begin
        ci = concentration_index(rand(rng, 50) .+ 0.1, randn(rng, 50))
        @test -1 <= ci <= 1
    end

    @testset "dissimilarity_index — in [0, 1]" begin
        a = rand(rng, 20) .* 10
        b = rand(rng, 20) .* 10
        d = dissimilarity_index(a, b)
        @test 0 <= d <= 1
    end

    @testset "isolation_exposure — valid ranges" begin
        a = rand(rng, 15) .* 5; b = rand(rng, 15) .* 5
        r = isolation_exposure(a, b)
        @test 0 <= r.isolation <= 1
        @test 0 <= r.exposure  <= 1
    end

    @testset "fairness_audit — returns FairnessAudit" begin
        fa = fairness_audit(probs, ŷ, y, groups; ses_var=ses)
        @test fa isa FairnessAudit
        @test isa(fa.overall_fair, Bool)
        @test 0 <= fa.gini <= 1
    end

    @testset "oaxaca_blinder — explained + unexplained ≈ total" begin
        g1 = groups .== "rural"; g2 = groups .== "urban"
        ob = oaxaca_blinder(X_feat[g1, :], Float64.(y[g1]),
                             X_feat[g2, :], Float64.(y[g2]);
                             feature_names=["f1","f2","f3","f4"])
        @test ob isa OaxacaResult
        @test abs(ob.explained + ob.unexplained - ob.total_gap) < 0.01
        @test !isempty(ob.feature_contributions)
    end

    @testset "theil_decompose — between + within ≈ total" begin
        td = theil_decompose(probs, groups)
        @test td isa TheilDecomposition
        @test abs(td.between + td.within - td.total) < 0.01
        @test length(td.groups) == 2
    end

    @testset "concentration_curve — monotone" begin
        cc = concentration_curve(probs, ses; n_points=20)
        @test nrow(cc) == 21
        @test all(diff(cc.cum_population) .>= 0)
    end

    @testset "slope_index_inequality — returns SII and RII" begin
        r = slope_index_inequality(probs, ses)
        @test isfinite(r.sii)
        @test isfinite(r.rii)
    end

    @testset "threshold_sweep — correct rows" begin
        ts = threshold_sweep(probs, y, groups; thresholds=0.1:0.1:0.9)
        @test nrow(ts) == 9
        @test hasproperty(ts, :dp_diff)
        @test all(0 .<= ts.accuracy .<= 1)
    end

    @testset "equalise_tpr — returns Dict with thresholds" begin
        threshs = equalise_tpr(probs, y, groups)
        @test haskey(threshs, "rural")
        @test haskey(threshs, "urban")
        @test all(0 < t < 1 for t in values(threshs))
    end

    @testset "equalise_fpr — valid thresholds" begin
        threshs = equalise_fpr(probs, y, groups)
        @test all(0 < t < 1 for t in values(threshs))
    end

    @testset "apply_group_thresholds — binary output" begin
        threshs = Dict("rural" => 0.4, "urban" => 0.6)
        ŷ2 = apply_group_thresholds(probs, groups, threshs)
        @test all(ŷ2 .∈ [[0, 1]])
    end

    @testset "platt_calibrate_by_group — calibration params finite" begin
        cp = platt_calibrate_by_group(probs, y, groups; n_iter=50)
        @test haskey(cp, "rural")
        @test isfinite(cp["rural"].a) && isfinite(cp["rural"].b)
    end

    @testset "apply_group_calibration — probs in (0,1)" begin
        cp = platt_calibrate_by_group(probs, y, groups; n_iter=30)
        p_cal = apply_group_calibration(probs, groups, cp)
        @test all(0 .< p_cal .< 1)
    end

    @testset "equity_report — generates report" begin
        r = equity_report(probs, y, groups;
                           X_features=X_feat,
                           ses_var=ses,
                           model_name="TestModel")
        @test r isa EquityReport
        @test r.n_total == n
        @test r.n_groups == 2
    end

end  # @testset
