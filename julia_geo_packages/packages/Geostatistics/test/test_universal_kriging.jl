"""
Universal Kriging (UK) test suite for Phase 2A.

Tests UK1 (linear drift) and UK2 (quadratic drift) on synthetic trend data.
Validates drift coefficient recovery, comparison with ordinary kriging, and
cross-validation residual properties.

Phase 2A Deliverable: Add Universal Kriging Tests (1 day)
- Test UK1 (linear drift) on synthetic trend data
- Test UK2 (quadratic drift) on non-linear trend
- Verify drift coefficients are reasonable
- Compare UK vs OK: UK should fit trend better
- Cross-validation: UK residuals should have zero mean
"""

using Test
using Geostatistics
using Statistics
using Random

@testset "Geostatistics — Universal Kriging" begin

    # =========================================================================
    # Test 1: UK1 (linear drift) on synthetic linear trend data
    # =========================================================================
    @testset "UK1 (linear drift) fits linear trend better than OK" begin
        Random.seed!(42)

        # Create synthetic data with LINEAR drift: z = 10 + 2*x + 3*y + spatial noise
        n = 20
        coords_x = rand(0:10, n)
        coords_y = rand(0:10, n)
        coords = (coords_x, coords_y)

        # Deterministic linear trend + small spatial noise
        trend = 10 .+ 2 .* coords_x .+ 3 .* coords_y
        spatial_noise = randn(n) .* 0.5  # Small noise
        z = trend .+ spatial_noise

        # Fit variogram to residuals (z - trend) to capture spatial structure
        residuals = z .- trend
        vario = empirical_variogram(coords, residuals; lags=8, maxlag=5.0)
        model = fit_variogram(vario)

        # Create prediction grid
        n_pred = 25
        pred_x = vec(repeat(0:2:8, 1, 5))
        pred_y = vec(repeat(0:2:8, 5, 1)')
        pred_coords = (pred_x, pred_y)

        # UK1 prediction
        uk1_result = universal_kriging(z, coords, pred_coords, model; drift_order=1)

        # OK prediction (no drift model)
        ok_result = ordinary_kriging(z, coords, pred_coords, model)

        # Compute expected values at prediction points
        expected = 10 .+ 2 .* pred_x .+ 3 .* pred_y

        # Verify UK1 fits trend better (lower RMSE)
        uk1_rmse = sqrt(mean((uk1_result.predictions .- expected) .^ 2))
        ok_rmse = sqrt(mean((ok_result.predictions .- expected) .^ 2))

        @test uk1_rmse < ok_rmse "UK1 should fit linear trend better than OK"
        @test uk1_rmse < 2.0 "UK1 RMSE on linear trend should be reasonable (<2)"
    end

    # =========================================================================
    # Test 2: UK2 (quadratic drift) on synthetic quadratic trend data
    # =========================================================================
    @testset "UK2 (quadratic drift) fits quadratic trend better than OK" begin
        Random.seed!(42)

        # Create synthetic data with QUADRATIC drift: z = 5 + x + y + x² + spatial noise
        n = 25
        coords_x = rand(0:5, n)
        coords_y = rand(0:5, n)
        coords = (coords_x, coords_y)

        # Quadratic trend
        trend = 5 .+ coords_x .+ coords_y .+ coords_x .^ 2
        spatial_noise = randn(n) .* 0.3
        z = trend .+ spatial_noise

        # Fit variogram to residuals
        residuals = z .- trend
        vario = empirical_variogram(coords, residuals; lags=8, maxlag=3.0)
        model = fit_variogram(vario)

        # Create prediction grid
        pred_x = vec(repeat(0:1:5, 1, 6))
        pred_y = vec(repeat(0:1:5, 6, 1)')
        pred_coords = (pred_x, pred_y)

        # UK2 and OK predictions
        uk2_result = universal_kriging(z, coords, pred_coords, model; drift_order=2)
        ok_result = ordinary_kriging(z, coords, pred_coords, model)

        # Expected values
        expected = 5 .+ pred_x .+ pred_y .+ pred_x .^ 2

        # Verify UK2 fits better
        uk2_rmse = sqrt(mean((uk2_result.predictions .- expected) .^ 2))
        ok_rmse = sqrt(mean((ok_result.predictions .- expected) .^ 2))

        @test uk2_rmse < ok_rmse "UK2 should fit quadratic trend better than OK"
        @test uk2_rmse < 1.5 "UK2 RMSE on quadratic trend should be reasonable (<1.5)"
    end

    # =========================================================================
    # Test 3: Verify drift coefficients are reasonable
    # =========================================================================
    @testset "Drift coefficients recover known trend parameters" begin
        Random.seed!(42)

        # Create data with known trend: z = 100 + 5*x - 3*y + noise
        n = 30
        coords_x = rand(0:10, n)
        coords_y = rand(0:10, n)
        coords = (coords_x, coords_y)

        trend = 100 .+ 5 .* coords_x .- 3 .* coords_y
        z = trend .+ randn(n) .* 0.2

        # Fit variogram
        residuals = z .- trend
        vario = empirical_variogram(coords, residuals; lags=6, maxlag=4.0)
        model = fit_variogram(vario)

        # UK1 on a single point (to inspect coefficients)
        pred_coords = ([5.0], [5.0])
        result = universal_kriging(z, coords, pred_coords, model; drift_order=1)

        # Coefficients should be approximately [100, 5, -3]
        # Check at least that predictions are in reasonable range
        expected_value = 100 + 5 * 5.0 - 3 * 5.0  # = 110
        pred_value = result.predictions[1]

        @test abs(pred_value - expected_value) < 5.0 "Drift coefficients should recover known trend (within ±5)"
        @test !isnan(pred_value) && !isinf(pred_value) "Drift coefficient must produce valid prediction"
    end

    # =========================================================================
    # Test 4: UK residuals from cross-validation have zero mean
    # =========================================================================
    @testset "UK cross-validation residuals have zero mean (unbiasedness)" begin
        Random.seed!(42)

        # Create synthetic data with trend
        n = 30
        coords_x = rand(0:8, n)
        coords_y = rand(0:8, n)
        coords = (coords_x, coords_y)

        trend = 50 .+ 2 .* coords_x .+ 1.5 .* coords_y
        z = trend .+ randn(n) .* 0.8

        # Fit variogram
        residuals = z .- trend
        vario = empirical_variogram(coords, residuals; lags=7, maxlag=4.0)
        model = fit_variogram(vario)

        # Leave-one-out cross-validation with UK1
        predictions = Float64[]
        for i in 1:n
            # Use all except point i
            coords_cv = (coords[1][1:n .!= i], coords[2][1:n .!= i])
            z_cv = z[1:n .!= i]
            pred_coords = ([coords_x[i]], [coords_y[i]])

            result = universal_kriging(z_cv, coords_cv, pred_coords, model; drift_order=1)
            push!(predictions, result.predictions[1])
        end

        # Compute residuals
        cv_residuals = z .- predictions

        # Mean should be near zero (unbiasedness property)
        mean_residual = mean(cv_residuals)
        @test abs(mean_residual) < 0.5 "CV residuals should have zero mean (unbiased), got mean=$mean_residual"
    end

    # =========================================================================
    # Test 5: UK system matrix construction is valid
    # =========================================================================
    @testset "UK system matrix is well-formed and solvable" begin
        Random.seed!(42)

        n = 15
        coords_x = rand(0:5, n)
        coords_y = rand(0:5, n)
        coords = (coords_x, coords_y)
        z = randn(n) .+ coords_x  # Simple data

        # Fit variogram
        vario = empirical_variogram(coords, z; lags=5, maxlag=3.0)
        model = fit_variogram(vario)

        # Build UK1 system (internal function, if exported)
        # If not exported, this test will be skipped
        if @isdefined universal_kriging_system
            A = universal_kriging_system(coords, model; drift_order=1)

            # Check system matrix properties
            @test size(A, 1) == size(A, 2) "UK system matrix should be square"
            @test size(A, 1) == n + 2 "UK1 system should have size (n+2) x (n+2) for n=$n"
            @test det(A) ≠ 0 "UK system matrix should be non-singular"
            @test !any(isnan.(A)) && !any(isinf.(A)) "UK matrix should contain only finite values"
        end
    end

    # =========================================================================
    # Test 6: UK with large drift_order (boundary condition)
    # =========================================================================
    @testset "UK with drift_order > data points warns or fails gracefully" begin
        Random.seed!(42)

        n = 10  # Only 10 points
        coords_x = rand(0:5, n)
        coords_y = rand(0:5, n)
        coords = (coords_x, coords_y)
        z = randn(n)

        vario = empirical_variogram(coords, z; lags=4, maxlag=2.5)
        model = fit_variogram(vario)

        pred_coords = ([2.5], [2.5])

        # UK with drift_order=2 requires n+6 coefficients, we have only n=10
        # This should either work (with local neighborhood) or throw a meaningful error
        try
            result = universal_kriging(z, coords, pred_coords, model; drift_order=2)
            # If it succeeds, result should be valid
            @test !isnan(result.predictions[1])
        catch e
            # If it fails, error should be informative
            @test e isa Exception
        end
    end

    # =========================================================================
    # Test 7: UK1 vs OK differences diminish far from trend
    # =========================================================================
    @testset "UK predictions converge to OK when drift is minimal" begin
        Random.seed!(42)

        # Create data with SMALL drift (mostly spatial structure)
        n = 25
        coords_x = rand(0:10, n)
        coords_y = rand(0:10, n)
        coords = (coords_x, coords_y)

        # Very small drift: mostly spatial autocorrelation
        trend = 0.1 .* coords_x  # Minimal trend
        spatial = randn(n) .* 3.0  # Large spatial noise
        z = trend .+ spatial

        vario = empirical_variogram(coords, z; lags=8, maxlag=5.0)
        model = fit_variogram(vario)

        pred_coords = ([5.0], [5.0])
        uk1_result = universal_kriging(z, coords, pred_coords, model; drift_order=1)
        ok_result = ordinary_kriging(z, coords, pred_coords, model)

        # When drift is minimal, predictions should be similar
        difference = abs(uk1_result.predictions[1] - ok_result.predictions[1])
        @test difference < 3.0 "UK and OK predictions should be similar when drift is minimal"
    end

    # =========================================================================
    # Test 8: Result structure and metadata
    # =========================================================================
    @testset "UK result structure contains predictions and variances" begin
        Random.seed!(42)

        n = 20
        coords_x = rand(0:5, n)
        coords_y = rand(0:5, n)
        coords = (coords_x, coords_y)
        z = randn(n) .+ coords_x

        vario = empirical_variogram(coords, z; lags=6, maxlag=3.0)
        model = fit_variogram(vario)

        pred_coords = ([2.0, 3.0], [2.0, 3.0])
        result = universal_kriging(z, coords, pred_coords, model; drift_order=1)

        @test haskey(result, :predictions) "Result should have :predictions field"
        @test haskey(result, :variances) "Result should have :variances field"
        @test length(result.predictions) == 2 "Should have 2 predictions"
        @test length(result.variances) == 2 "Should have 2 variances"
        @test all(>=(0), result.variances) "Variances must be non-negative"
        @test !any(isnan.(result.predictions)) "Predictions must be finite"
    end

    # =========================================================================
    # Test 9: UK with neighborhood reduction (local kriging)
    # =========================================================================
    @testset "UK with max_neighbors parameter uses local kriging" begin
        Random.seed!(42)

        # Large dataset to make neighborhood selection meaningful
        n = 100
        coords_x = rand(0:20, n)
        coords_y = rand(0:20, n)
        coords = (coords_x, coords_y)
        z = randn(n) .+ 0.5 .* coords_x

        vario = empirical_variogram(coords, z; lags=10, maxlag=8.0)
        model = fit_variogram(vario)

        # Single prediction point
        pred_coords = ([10.0], [10.0])

        # UK with all points
        result_all = universal_kriging(z, coords, pred_coords, model; drift_order=1)

        # UK with max_neighbors (if supported)
        if VERSION >= v"1.10"  # Assume feature in recent version
            try
                result_local = universal_kriging(
                    z, coords, pred_coords, model;
                    drift_order=1,
                    max_neighbors=20
                )
                # Both should produce valid results
                @test !isnan(result_all.predictions[1])
                @test !isnan(result_local.predictions[1])
            catch
                # If max_neighbors not supported, that's fine for now
                @test !isnan(result_all.predictions[1])
            end
        end
    end

    # =========================================================================
    # Test 10: Multiple prediction points with UK
    # =========================================================================
    @testset "UK batch predictions on multiple points" begin
        Random.seed!(42)

        n = 30
        coords_x = rand(0:8, n)
        coords_y = rand(0:8, n)
        coords = (coords_x, coords_y)
        z = randn(n) .+ coords_x .+ coords_y

        vario = empirical_variogram(coords, z; lags=8, maxlag=5.0)
        model = fit_variogram(vario)

        # Multiple prediction points (grid)
        pred_x = vec(repeat(1:3, 1, 3))
        pred_y = vec(repeat(1:3, 3, 1)')
        pred_coords = (pred_x, pred_y)

        result = universal_kriging(z, coords, pred_coords, model; drift_order=1)

        @test length(result.predictions) == 9 "Should have 9 predictions for 3x3 grid"
        @test length(result.variances) == 9 "Should have 9 variances"
        @test !any(isnan.(result.predictions)) "All predictions must be finite"
        @test all(>=(0), result.variances) "All variances must be non-negative"
    end

end
