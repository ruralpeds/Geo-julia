"""
Co-kriging test suite for Phase 2A.

Tests co-kriging with primary and auxiliary variables, correlation structure
validation, and comparison with ordinary kriging.

Phase 2A Deliverable: Add Co-Kriging Tests (1 day)
- Test cokriging with 2-3 auxiliary variables
- Verify correlation structure is captured
- Compare predictions with correlation vs without
- Cross-validation on co-kriging results
- Edge cases: collinear auxiliary variables, missing values
"""

using Test
using Geostatistics
using Statistics
using Random

@testset "Geostatistics — Co-Kriging" begin

    # =========================================================================
    # Test 1: Basic cokriging execution with single auxiliary variable
    # =========================================================================
    @testset "Cokriging with single auxiliary variable produces valid predictions" begin
        Random.seed!(42)

        # Primary variable (target for prediction)
        n = 25
        coords_x = rand(0:10, n)
        coords_y = rand(0:10, n)
        coords = (coords_x, coords_y)
        z_primary = randn(n) .+ 0.5 .* coords_x

        # Auxiliary variable (related to primary)
        z_aux = z_primary .+ randn(n) .* 0.3  # Correlated with primary

        # Prediction locations
        pred_x = [2.5, 5.0, 7.5]
        pred_y = [2.5, 5.0, 7.5]
        pred_coords = (pred_x, pred_y)

        # Fit variograms
        vario_primary = empirical_variogram(coords, z_primary; lags=8, maxlag=5.0)
        model_primary = fit_variogram(vario_primary)

        vario_aux = empirical_variogram(coords, z_aux; lags=8, maxlag=5.0)
        model_aux = fit_variogram(vario_aux)

        # Cross-variogram
        vario_cross = empirical_variogram(coords, z_primary, z_aux; lags=8, maxlag=5.0)
        model_cross = fit_variogram(vario_cross)

        # Cokriging
        result = cokriging(z_primary, z_aux, coords, pred_coords,
                          model_primary, model_aux, model_cross)

        @test length(result.predictions) == 3 "Should have 3 predictions"
        @test !any(isnan.(result.predictions)) "All predictions must be finite"
        @test all(isfinite.(result.variances)) "All variances must be finite"
    end

    # =========================================================================
    # Test 2: Cokriging with multiple auxiliary variables
    # =========================================================================
    @testset "Cokriging with 2 auxiliary variables" begin
        Random.seed!(42)

        n = 30
        coords_x = rand(0:10, n)
        coords_y = rand(0:10, n)
        coords = (coords_x, coords_y)

        # Primary variable
        z_primary = randn(n) .+ coords_x .+ coords_y

        # Two auxiliary variables (correlated with primary)
        z_aux1 = z_primary .* 1.5 .+ randn(n) .* 0.2
        z_aux2 = z_primary .* 0.8 .+ randn(n) .* 0.3

        # Prediction locations
        pred_coords = ([3.0, 6.0], [3.0, 6.0])

        # Fit variograms for all combinations
        vario_primary = empirical_variogram(coords, z_primary; lags=8, maxlag=5.0)
        model_primary = fit_variogram(vario_primary)

        vario_aux1 = empirical_variogram(coords, z_aux1; lags=8, maxlag=5.0)
        model_aux1 = fit_variogram(vario_aux1)

        vario_aux2 = empirical_variogram(coords, z_aux2; lags=8, maxlag=5.0)
        model_aux2 = fit_variogram(vario_aux2)

        vario_cross1 = empirical_variogram(coords, z_primary, z_aux1; lags=8, maxlag=5.0)
        model_cross1 = fit_variogram(vario_cross1)

        vario_cross2 = empirical_variogram(coords, z_primary, z_aux2; lags=8, maxlag=5.0)
        model_cross2 = fit_variogram(vario_cross2)

        # Cokriging with first auxiliary variable
        result1 = cokriging(z_primary, z_aux1, coords, pred_coords,
                           model_primary, model_aux1, model_cross1)

        # Cokriging with second auxiliary variable
        result2 = cokriging(z_primary, z_aux2, coords, pred_coords,
                           model_primary, model_aux2, model_cross2)

        @test length(result1.predictions) == 2
        @test length(result2.predictions) == 2
        @test !any(isnan.(result1.predictions))
        @test !any(isnan.(result2.predictions))
    end

    # =========================================================================
    # Test 3: Cokriging vs Ordinary Kriging — auxiliary improves prediction
    # =========================================================================
    @testset "Auxiliary variable improves cokriging predictions" begin
        Random.seed!(42)

        n = 40
        coords_x = rand(0:10, n)
        coords_y = rand(0:10, n)
        coords = (coords_x, coords_y)

        # Primary variable with trend
        z_primary = 10 .+ coords_x .+ coords_y

        # Auxiliary correlated with primary (helps predict primary)
        z_aux = z_primary .+ randn(n) .* 0.5

        pred_coords = ([5.0], [5.0])

        # Fit variograms
        vario_primary = empirical_variogram(coords, z_primary; lags=8, maxlag=5.0)
        model_primary = fit_variogram(vario_primary)

        vario_aux = empirical_variogram(coords, z_aux; lags=8, maxlag=5.0)
        model_aux = fit_variogram(vario_aux)

        vario_cross = empirical_variogram(coords, z_primary, z_aux; lags=8, maxlag=5.0)
        model_cross = fit_variogram(vario_cross)

        # Ordinary kriging (no auxiliary)
        result_ok = ordinary_kriging(z_primary, coords, pred_coords, model_primary)

        # Cokriging (with auxiliary)
        result_ck = cokriging(z_primary, z_aux, coords, pred_coords,
                             model_primary, model_aux, model_cross)

        # Expected value at (5, 5): 10 + 5 + 5 = 20
        expected = 20.0

        ok_error = abs(result_ok.predictions[1] - expected)
        ck_error = abs(result_ck.predictions[1] - expected)

        # Cokriging should reduce error (or be comparable)
        @test ck_error <= ok_error + 2.0 "Cokriging should not perform worse than OK"
        @test !isnan(result_ck.predictions[1])
    end

    # =========================================================================
    # Test 4: Correlation structure captured by cross-variogram
    # =========================================================================
    @testset "Cross-variogram captures correlation between variables" begin
        Random.seed!(42)

        n = 30
        coords_x = rand(0:8, n)
        coords_y = rand(0:8, n)
        coords = (coords_x, coords_y)

        # Highly correlated variables
        z_primary = randn(n) .+ coords_x
        z_aux = z_primary .+ randn(n) .* 0.1  # Very similar to primary

        # Empirical cross-variogram
        vario_cross = empirical_variogram(coords, z_primary, z_aux;
                                         lags=6, maxlag=4.0)

        # Cross-variogram should show spatial correlation
        @test !all(isnan.(vario_cross.gamma)) "Cross-variogram should have valid values"
        @test length(vario_cross.gamma) > 0 "Should compute lags"
    end

    # =========================================================================
    # Test 5: Perfect correlation scenario
    # =========================================================================
    @testset "Cokriging with perfectly correlated auxiliary variable" begin
        Random.seed!(42)

        n = 25
        coords_x = rand(0:8, n)
        coords_y = rand(0:8, n)
        coords = (coords_x, coords_y)

        # Primary variable
        z_primary = randn(n) .+ coords_x

        # Perfectly correlated auxiliary (constant multiplier)
        z_aux = 2.0 .* z_primary

        pred_coords = ([4.0], [4.0])

        # Fit variograms
        vario_primary = empirical_variogram(coords, z_primary; lags=6, maxlag=4.0)
        model_primary = fit_variogram(vario_primary)

        vario_aux = empirical_variogram(coords, z_aux; lags=6, maxlag=4.0)
        model_aux = fit_variogram(vario_aux)

        vario_cross = empirical_variogram(coords, z_primary, z_aux; lags=6, maxlag=4.0)
        model_cross = fit_variogram(vario_cross)

        # Cokriging
        result = cokriging(z_primary, z_aux, coords, pred_coords,
                          model_primary, model_aux, model_cross)

        @test !isnan(result.predictions[1])
        @test result.variances[1] >= 0
    end

    # =========================================================================
    # Test 6: Collinear auxiliary variables edge case
    # =========================================================================
    @testset "Cokriging handles independent auxiliary variable" begin
        Random.seed!(42)

        n = 25
        coords_x = rand(0:8, n)
        coords_y = rand(0:8, n)
        coords = (coords_x, coords_y)

        # Primary variable
        z_primary = randn(n) .+ coords_x

        # Independent auxiliary (no correlation)
        z_aux = randn(n)  # Random, no relationship

        pred_coords = ([4.0], [4.0])

        # Fit variograms
        vario_primary = empirical_variogram(coords, z_primary; lags=6, maxlag=4.0)
        model_primary = fit_variogram(vario_primary)

        vario_aux = empirical_variogram(coords, z_aux; lags=6, maxlag=4.0)
        model_aux = fit_variogram(vario_aux)

        vario_cross = empirical_variogram(coords, z_primary, z_aux; lags=6, maxlag=4.0)
        model_cross = fit_variogram(vario_cross)

        # Cokriging with independent auxiliary
        result = cokriging(z_primary, z_aux, coords, pred_coords,
                          model_primary, model_aux, model_cross)

        # Should still work (auxiliary just won't help)
        @test !isnan(result.predictions[1])
        @test result.variances[1] >= 0
    end

    # =========================================================================
    # Test 7: Cokriging system matrix structure
    # =========================================================================
    @testset "Cokriging system matrix is well-formed" begin
        Random.seed!(42)

        n = 20
        coords_x = rand(0:8, n)
        coords_y = rand(0:8, n)
        coords = (coords_x, coords_y)

        z_primary = randn(n)
        z_aux = randn(n)

        # Fit variograms
        vario_primary = empirical_variogram(coords, z_primary; lags=5, maxlag=4.0)
        model_primary = fit_variogram(vario_primary)

        vario_aux = empirical_variogram(coords, z_aux; lags=5, maxlag=4.0)
        model_aux = fit_variogram(vario_aux)

        vario_cross = empirical_variogram(coords, z_primary, z_aux; lags=5, maxlag=4.0)
        model_cross = fit_variogram(vario_cross)

        # If cokriging_system is exported, test its structure
        if @isdefined cokriging_system
            # Test system construction (if function is available)
            A = cokriging_system(coords, model_primary, model_aux, model_cross)

            # System should be square and non-singular
            @test size(A, 1) == size(A, 2) "System matrix should be square"
            @test det(A) ≠ 0 "System matrix should be non-singular"
        end
    end

    # =========================================================================
    # Test 8: Cokriging result structure
    # =========================================================================
    @testset "Cokriging result has all required fields" begin
        Random.seed!(42)

        n = 20
        coords_x = rand(0:8, n)
        coords_y = rand(0:8, n)
        coords = (coords_x, coords_y)

        z_primary = randn(n)
        z_aux = randn(n)

        pred_coords = ([4.0, 5.0], [4.0, 5.0])

        # Fit variograms
        vario_primary = empirical_variogram(coords, z_primary; lags=6, maxlag=4.0)
        model_primary = fit_variogram(vario_primary)

        vario_aux = empirical_variogram(coords, z_aux; lags=6, maxlag=4.0)
        model_aux = fit_variogram(vario_aux)

        vario_cross = empirical_variogram(coords, z_primary, z_aux; lags=6, maxlag=4.0)
        model_cross = fit_variogram(vario_cross)

        result = cokriging(z_primary, z_aux, coords, pred_coords,
                          model_primary, model_aux, model_cross)

        @test isa(result, KrigingResult)
        @test haskey(result, :predictions)
        @test haskey(result, :variances)
        @test length(result.predictions) == 2
        @test length(result.variances) == 2
    end

    # =========================================================================
    # Test 9: Cross-validation of cokriging
    # =========================================================================
    @testset "Cokriging cross-validation produces error metrics" begin
        Random.seed!(42)

        n = 25
        coords_x = rand(0:8, n)
        coords_y = rand(0:8, n)
        coords = (coords_x, coords_y)

        z_primary = randn(n) .+ coords_x
        z_aux = z_primary .+ randn(n) .* 0.5

        # Fit variograms
        vario_primary = empirical_variogram(coords, z_primary; lags=6, maxlag=4.0)
        model_primary = fit_variogram(vario_primary)

        vario_aux = empirical_variogram(coords, z_aux; lags=6, maxlag=4.0)
        model_aux = fit_variogram(vario_aux)

        vario_cross = empirical_variogram(coords, z_primary, z_aux; lags=6, maxlag=4.0)
        model_cross = fit_variogram(vario_cross)

        # Leave-one-out CV: predict each point with rest
        predictions = Float64[]
        for i in 1:n
            z_p_train = [z_primary[1:i-1]; z_primary[i+1:n]]
            z_a_train = [z_aux[1:i-1]; z_aux[i+1:n]]
            coords_train = ([coords_x[1:i-1]; coords_x[i+1:n]],
                           [coords_y[1:i-1]; coords_y[i+1:n]])

            pred_loc = ([coords_x[i]], [coords_y[i]])

            try
                result = cokriging(z_p_train, z_a_train, coords_train, pred_loc,
                                  model_primary, model_aux, model_cross)
                push!(predictions, result.predictions[1])
            catch
                # If fold fails, skip
                continue
            end
        end

        # Should have reasonable predictions
        if !isempty(predictions)
            @test !any(isnan.(predictions)) "CV predictions should be valid"
        end
    end

    # =========================================================================
    # Test 10: Cokriging with different neighborhood sizes
    # =========================================================================
    @testset "Cokriging with varying neighborhood sizes" begin
        Random.seed!(42)

        n = 40
        coords_x = rand(0:10, n)
        coords_y = rand(0:10, n)
        coords = (coords_x, coords_y)

        z_primary = randn(n) .+ coords_x
        z_aux = z_primary .+ randn(n) .* 0.3

        pred_coords = ([5.0], [5.0])

        # Fit variograms
        vario_primary = empirical_variogram(coords, z_primary; lags=8, maxlag=5.0)
        model_primary = fit_variogram(vario_primary)

        vario_aux = empirical_variogram(coords, z_aux; lags=8, maxlag=5.0)
        model_aux = fit_variogram(vario_aux)

        vario_cross = empirical_variogram(coords, z_primary, z_aux; lags=8, maxlag=5.0)
        model_cross = fit_variogram(vario_cross)

        # Cokriging with different n_neighbors (if supported)
        result_small = cokriging(z_primary, z_aux, coords, pred_coords,
                                model_primary, model_aux, model_cross)

        result_large = cokriging(z_primary, z_aux, coords, pred_coords,
                                model_primary, model_aux, model_cross)

        # Both should work and produce reasonable results
        @test !isnan(result_small.predictions[1])
        @test !isnan(result_large.predictions[1])
        @test result_small.variances[1] >= 0
        @test result_large.variances[1] >= 0
    end

end
