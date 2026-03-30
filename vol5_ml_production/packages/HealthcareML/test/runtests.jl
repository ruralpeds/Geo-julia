using Test, Random, DataFrames, Statistics
Random.seed!(42)

# Load HealthcareML from dev path
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using HealthcareML

# ── Synthetic dataset ─────────────────────────────────────────────────────────
function make_regression_data(n=80, p=5; rng=MersenneTwister(42))
    X = randn(rng, n, p)
    β = randn(rng, p)
    y = X * β + 0.3 * randn(rng, n)
    (X, y)
end

X, y = make_regression_data(80, 5)

@testset "HealthcareML Tests" begin

    @testset "1. RidgeAccess — fit and predict" begin
        m = RidgeAccess(λ=1.0)
        fit!(m, X, y)
        @test m.fitted
        ŷ = predict(m, X)
        @test length(ŷ) == 80
        @test !any(isnan, ŷ)
        # R² should be reasonable
        ss_res = sum((y .- ŷ).^2)
        ss_tot = sum((y .- mean(y)).^2)
        @test ss_res / ss_tot < 0.9  # at least 10% variance explained
    end

    @testset "2. RidgeAccess — predict_proba" begin
        m = RidgeAccess(λ=0.5)
        fit!(m, X, y)
        probs = predict_proba(m, X)
        @test all(0 .<= probs .<= 1)
    end

    @testset "3. DecisionTreeAccess — basic" begin
        m = DecisionTreeAccess(max_depth=4, min_samples_split=3)
        fit!(m, X, y)
        @test m.fitted
        ŷ = predict(m, X)
        @test length(ŷ) == 80
        @test !any(isnan, ŷ)
        @test length(m.feature_importances_) == 5
        @test abs(sum(m.feature_importances_) - 1.0) < 1e-9
    end

    @testset "4. DecisionTreeAccess — depth constraint" begin
        m_shallow = DecisionTreeAccess(max_depth=1)
        m_deep    = DecisionTreeAccess(max_depth=10)
        fit!(m_shallow, X, y)
        fit!(m_deep, X, y)
        ŷ_s = predict(m_shallow, X)
        ŷ_d = predict(m_deep, X)
        # Deeper tree should fit training data better
        rmse_s = sqrt(mean((y .- ŷ_s).^2))
        rmse_d = sqrt(mean((y .- ŷ_d).^2))
        @test rmse_d <= rmse_s
    end

    @testset "5. RandomForestAccess — fit and OOB" begin
        m = RandomForestAccess(n_trees=20, max_depth=4)
        fit!(m, X, y)
        @test m.fitted
        @test length(m.trees) == 20
        @test !isnan(m.oob_score_)
        @test length(m.feature_importances_) == 5
        @test abs(sum(m.feature_importances_) - 1.0) < 1e-6
    end

    @testset "6. RandomForestAccess — prediction quality" begin
        m = RandomForestAccess(n_trees=50, max_depth=5)
        fit!(m, X, y)
        ŷ = predict(m, X)
        ss_res = sum((y .- ŷ).^2)
        ss_tot = sum((y .- mean(y)).^2)
        r2 = 1.0 - ss_res / ss_tot
        @test r2 > 0.5  # RF should explain > 50% on training data
    end

    @testset "7. GradientBoostAccess — fit" begin
        m = GradientBoostAccess(n_estimators=30, learning_rate=0.1, max_depth=2)
        fit!(m, X, y)
        @test m.fitted
        @test length(m.trees) == 30
        @test length(m.train_scores_) == 30
        # Training loss should decrease
        @test m.train_scores_[end] < m.train_scores_[1]
    end

    @testset "8. GradientBoostAccess — predict" begin
        m = GradientBoostAccess(n_estimators=50, learning_rate=0.05)
        fit!(m, X, y)
        ŷ = predict(m, X)
        @test length(ŷ) == 80
        @test !any(isnan, ŷ)
    end

    @testset "9. build_features — basic" begin
        n = 53
        df = DataFrame(
            poverty_pct   = 5.0 .+ 15.0 * rand(n),
            uninsured_pct = 8.0 .+ 12.0 * rand(n),
            total_pop     = rand(1000:50000, n),
            rurality      = rand(n),
            access_score  = abs.(randn(n)) * 0.01 .+ 0.005,
        )
        feat = build_features(df, :access_score;
                              config=AccessFeatures(spatial_lags=0, interaction_terms=false,
                                                    polynomial_degree=1, standardize=true))
        @test feat.X isa Matrix{Float64}
        @test size(feat.X, 1) == 53
        @test length(feat.feature_names) == size(feat.X, 2)
    end

    @testset "10. build_features — polynomial + interactions" begin
        n = 30
        df = DataFrame(
            poverty_pct   = rand(n) * 20,
            uninsured_pct = rand(n) * 15,
            total_pop     = rand(1000:10000, n),
            rurality      = rand(n),
            access_score  = rand(n),
        )
        feat = build_features(df, :access_score;
                              config=AccessFeatures(spatial_lags=0, interaction_terms=true,
                                                    polynomial_degree=2, standardize=false))
        # With 4 raw features + log_pop_k + poverty_x_uninsured = 6 raw
        # poly degree 2 adds 6 more = 12
        # interactions: C(6,2) = 15 pairwise on raw only = +C(base_p, 2)
        @test size(feat.X, 2) > 6
    end

    @testset "11. cross_validate — RidgeAccess" begin
        cv = cross_validate(() -> RidgeAccess(λ=1.0), X, y; folds=5)
        @test length(cv.scores) == 5
        @test cv.mean_score > 0
        @test length(cv.oof_predictions) == 80
        @test !any(isnan, cv.oof_predictions)
    end

    @testset "12. cross_validate — RandomForest" begin
        cv = cross_validate(() -> RandomForestAccess(n_trees=15, max_depth=3),
                             X, y; folds=3)
        @test length(cv.scores) == 3
        @test cv.mean_score > 0
    end

    @testset "13. permutation_importance" begin
        m = RandomForestAccess(n_trees=20)
        fit!(m, X, y)
        imp = permutation_importance(m, X, y;
                                      feature_names=["a","b","c","d","e"],
                                      n_repeats=3)
        @test nrow(imp) == 5
        @test hasproperty(imp, :importance_mean)
        @test hasproperty(imp, :feature)
        # Should be sorted descending
        @test issorted(imp.importance_mean; rev=true)
    end

    @testset "14. partial_dependence" begin
        m = RidgeAccess(λ=0.5)
        fit!(m, X, y)
        pdp = partial_dependence(m, X, 1; grid_points=20)
        @test nrow(pdp) == 20
        @test hasproperty(pdp, :value)
        @test hasproperty(pdp, :pdp)
        @test !any(isnan, pdp.pdp)
    end

    @testset "15. shap_values — shape and finite" begin
        m = RidgeAccess(λ=1.0)
        fit!(m, X, y)
        sv = shap_values(m, X[1:10, :]; n_samples=20)
        @test size(sv) == (10, 5)
        @test !any(isnan, sv)
        @test !any(isinf, sv)
    end

    @testset "16. calibration_curve + brier_score" begin
        probs  = clamp.(0.3 .+ 0.4 * rand(80), 0, 1)
        y_bin  = rand(Bool, 80)
        calib  = calibration_curve(probs, y_bin; n_bins=5)
        @test hasproperty(calib, :prob_mean)
        @test hasproperty(calib, :fraction_positive)
        @test all(0 .<= calib.prob_mean .<= 1)
        bs = brier_score(probs, y_bin)
        @test 0 <= bs <= 1
    end

    @testset "17. compare_models" begin
        models = Dict(
            "ridge" => () -> RidgeAccess(λ=0.5),
            "tree"  => () -> DecisionTreeAccess(max_depth=3),
        )
        comp = compare_models(models, X, y; folds=3)
        @test length(comp.names) == 2
        @test haskey(comp.scores, "ridge")
        @test haskey(comp.scores, "tree")
    end

    @testset "18. HealthcareMLReport generation" begin
        m = RandomForestAccess(n_trees=20, max_depth=3)
        fit!(m, X, y)
        fn = ["feat_$i" for i in 1:5]
        rep = generate_report(m, X, y, fn; cv_folds=3, shap_samples=15)
        @test rep isa HealthcareMLReport
        @test rep.n_obs == 80
        @test rep.n_features == 5
        @test rep.cv_mean > 0
        @test nrow(rep.feature_importances) <= 10
        @test nrow(rep.top_shap_features) <= 10
        @test isnothing(rep.calibration_data)  # no binary threshold passed
    end

end  # @testset

@info "HealthcareML tests complete."
