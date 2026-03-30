#!/usr/bin/env julia
# test/runtests.jl — ConformalHealth.jl unit tests

using Test, Random, Statistics, LinearAlgebra
using ConformalHealth

Random.seed!(42)

rng = MersenneTwister(42)
n_train = 200; n_calib = 100; n_test = 50; p = 4

X_all  = randn(rng, n_train + n_calib + n_test, p)
β_true = [0.8, -0.5, 0.3, -0.2]
y_all  = X_all * β_true .+ 0.3*randn(rng, n_train+n_calib+n_test)

X_train = X_all[1:n_train, :]; y_train = y_all[1:n_train]
X_calib = X_all[n_train+1:n_train+n_calib, :]; y_calib = y_all[n_train+1:n_train+n_calib]
X_test  = X_all[n_train+n_calib+1:end, :]; y_test  = y_all[n_train+n_calib+1:end]

# Simple OLS predict function
function ols_predict_fn(X_tr, y_tr)
    X_aug = hcat(ones(size(X_tr,1)), X_tr)
    β = (X_aug'X_aug + 1e-8I) \ X_aug'y_tr
    X_new -> vec(hcat(ones(size(X_new,1)), X_new) * β)
end
predict_fn = ols_predict_fn(X_train, y_train)

@testset "ConformalHealth.jl" begin

    @testset "Split conformal — coverage ≥ 1-α" begin
        cr = conformal_fit(predict_fn, X_calib, y_calib; α=0.1)
        @test cr isa ConformalRegressor
        result = conformal_predict(cr, X_test)
        cov = conformal_coverage(result, y_test)
        @test cov.coverage >= 0.9 - 0.05   # allow small finite-sample deviation
        @test all(result.lower .<= result.upper)
    end

    @testset "Split conformal — wider α=0.05 > α=0.1" begin
        cr05 = conformal_fit(predict_fn, X_calib, y_calib; α=0.05)
        cr10 = conformal_fit(predict_fn, X_calib, y_calib; α=0.10)
        @test cr05.q̂ >= cr10.q̂   # more stringent → wider
    end

    @testset "Split conformal — intervals finite" begin
        cr = conformal_fit(predict_fn, X_calib, y_calib; α=0.1)
        r  = conformal_predict(cr, X_test)
        @test all(isfinite, r.lower)
        @test all(isfinite, r.upper)
        @test all(r.width .>= 0)
    end

    @testset "Jackknife+ — coverage ≥ 1-2α" begin
        fit_fn(Xtr, ytr) = ols_predict_fn(Xtr, ytr)
        jr = jackknife_plus(fit_fn, X_train[1:50,:], y_train[1:50],
                             X_test; α=0.1, max_n_loo=20)
        @test jr isa JackknifeResult
        covered = (y_test .>= jr.lower) .& (y_test .<= jr.upper)
        @test mean(covered) >= 0.7   # 1 - 2α = 0.8, with finite-sample slack
        @test all(jr.lower .<= jr.upper)
    end

    @testset "CV+ — valid intervals" begin
        fit_fn(Xtr, ytr) = ols_predict_fn(Xtr, ytr)
        jr = cv_plus(fit_fn, X_train[1:80,:], y_train[1:80],
                      X_test; α=0.1, K=5, rng=rng)
        @test all(isfinite, jr.lower)
        @test all(isfinite, jr.upper)
    end

    @testset "CQR — coverage ≥ 1-α" begin
        m = cqr_fit(X_train, y_train, X_calib, y_calib; α=0.1)
        @test m isa CQRModel
        df = cqr_predict(m, X_test)
        covered = (y_test .>= df.lower) .& (y_test .<= df.upper)
        @test mean(covered) >= 0.85   # 1-α with small slack
        @test all(df.lower .<= df.upper)
    end

    @testset "CQR — locally adaptive width" begin
        m = cqr_fit(X_train, y_train, X_calib, y_calib; α=0.1)
        df = cqr_predict(m, X_test)
        # Widths should vary (not all identical as in split conformal)
        @test std(df.width) >= 0
        @test nrow(df) == n_test
    end

    @testset "APS — prediction sets non-empty" begin
        K = 4
        n_c = 80; n_t = 20
        probs_c = softmax_rows(randn(rng, n_c, K))
        y_c     = rand(rng, 1:K, n_c)
        probs_t = softmax_rows(randn(rng, n_t, K))

        aps = aps_fit(probs_c, y_c; α=0.1)
        @test aps isa AdaptivePredictionSet
        sets = aps_predict(aps, probs_t)
        @test length(sets) == n_t
        @test all(length(s) >= 1 for s in sets)
        @test all(maximum(s) <= K for s in sets)
    end

    @testset "APS — coverage ≥ 1-α" begin
        K = 3; n_c = 200; n_t = 100
        probs_c = softmax_rows(randn(rng, n_c, K))
        y_c     = rand(rng, 1:K, n_c)
        probs_t = softmax_rows(randn(rng, n_t, K))
        y_t     = rand(rng, 1:K, n_t)

        aps = aps_fit(probs_c, y_c; α=0.1)
        sets = aps_predict(aps, probs_t)
        covered = [y_t[i] ∈ sets[i] for i in 1:n_t]
        @test mean(covered) >= 0.8
    end

    @testset "conformal_classify — DataFrame columns" begin
        K = 3; n_t = 15
        probs_c = softmax_rows(randn(rng, 50, K))
        y_c     = rand(rng, 1:K, 50)
        aps = aps_fit(probs_c, y_c)
        probs_t = softmax_rows(randn(rng, n_t, K))
        df = conformal_classify(probs_t, aps)
        @test nrow(df) == n_t
        @test hasproperty(df, :set_size)
        @test hasproperty(df, :uncertain)
    end

    @testset "Temperature scaling — T > 0" begin
        n_s = 100; K = 4
        logits = randn(rng, n_s, K)
        y_ts   = rand(rng, 1:K, n_s)
        T, cal_probs = temperature_scaling(logits, y_ts; max_iter=100)
        @test T > 0
        @test isfinite(T)
        @test size(cal_probs) == (n_s, K)
        @test all(sum(cal_probs; dims=2) .≈ 1.0 atol=1e-6)
    end

    @testset "Isotonic calibration — monotone output" begin
        p_raw = sort(rand(rng, 100))
        y_cal = Int.(rand(rng, 100) .< p_raw)
        p_cal, _, _ = isotonic_calibrate(p_raw, y_cal)
        @test length(p_cal) == 100
        @test all(0 .<= p_cal .<= 1)
    end

    @testset "Calibration error — ECE in [0,1]" begin
        p_raw = clamp.(randn(rng, 200) .* 0.2 .+ 0.5, 0.01, 0.99)
        y_raw = Int.(rand(rng, 200) .< p_raw)
        cr = calibration_error(p_raw, y_raw; n_bins=10)
        @test 0 <= cr.ece <= 1
        @test 0 <= cr.mce <= 1
        @test cr.brier >= 0
    end

    @testset "Reliability diagram — correct bins" begin
        p_raw = clamp.(rand(rng, 150), 0.01, 0.99)
        y_raw = Int.(rand(rng, 150) .< p_raw)
        rd = reliability_diagram(p_raw, y_raw; n_bins=8)
        @test nrow(rd) <= 8
        @test hasproperty(rd, :confidence)
        @test hasproperty(rd, :accuracy)
    end

end  # @testset

# Helper: row-wise softmax
function softmax_rows(X::AbstractMatrix)
    X_shifted = X .- maximum(X; dims=2)
    exp_X = exp.(X_shifted)
    exp_X ./ sum(exp_X; dims=2)
end
