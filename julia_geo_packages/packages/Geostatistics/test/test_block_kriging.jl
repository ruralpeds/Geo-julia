"""
Block Kriging test suite for Phase 2A.

Tests area-level aggregation, variance reduction property, numerical integration
convergence, and multiple block size scenarios.

Phase 2A Deliverable: Add Block Kriging Tests (1 day)
- Test area-level aggregation for rectangular blocks
- Compare block kriging variance vs point variance
- Verify uncertainty decreases with larger blocks
- Numerical integration convergence (tolerance sensitivity)
- Multiple block sizes: small, medium, large
"""

using Test
using Geostatistics
using Statistics
using Random

@testset "Geostatistics — Block Kriging" begin

    # =========================================================================
    # Test 1: Basic block kriging execution
    # =========================================================================
    @testset "Block kriging produces valid predictions for single block" begin
        Random.seed!(42)

        # Create training data
        n = 25
        coords_x = rand(0:10, n)
        coords_y = rand(0:10, n)
        coords = (coords_x, coords_y)
        z = randn(n) .+ 0.5 .* coords_x

        # Fit variogram
        vario = empirical_variogram(coords, z; lags=8, maxlag=5.0)
        model = fit_variogram(vario)

        # Single block centered at (5, 5)
        block_centers = [(5.0, 5.0)]
        result = block_kriging(z, coords, block_centers, model; block_size=2.0, n_grid=5)

        @test length(result.predictions) == 1 "Should have 1 prediction for 1 block"
        @test !isnan(result.predictions[1]) "Block prediction must be finite"
        @test result.variances[1] > 0 "Block variance must be positive"
        @test result.variances[1] <= 1.0 "Block variance should be reasonable"
    end

    # =========================================================================
    # Test 2: Multiple blocks
    # =========================================================================
    @testset "Block kriging on multiple blocks" begin
        Random.seed!(42)

        n = 40
        coords_x = rand(0:12, n)
        coords_y = rand(0:12, n)
        coords = (coords_x, coords_y)
        z = randn(n) .+ coords_x

        vario = empirical_variogram(coords, z; lags=10, maxlag=6.0)
        model = fit_variogram(vario)

        # 4 blocks in a 2×2 grid
        block_centers = [
            (2.0, 2.0), (6.0, 2.0),
            (2.0, 6.0), (6.0, 6.0)
        ]

        result = block_kriging(z, coords, block_centers, model; block_size=3.0, n_grid=5)

        @test length(result.predictions) == 4 "Should have 4 predictions"
        @test length(result.variances) == 4 "Should have 4 variances"
        @test !any(isnan.(result.predictions)) "All predictions must be finite"
        @test all(>=(0), result.variances) "All variances must be non-negative"
    end

    # =========================================================================
    # Test 3: Block kriging variance < point kriging variance
    # =========================================================================
    @testset "Block kriging variance is smaller than point kriging" begin
        Random.seed!(42)

        # Create training data
        n = 30
        coords_x = rand(0:8, n)
        coords_y = rand(0:8, n)
        coords = (coords_x, coords_y)
        z = randn(n) .+ coords_x .+ coords_y

        vario = empirical_variogram(coords, z; lags=8, maxlag=4.5)
        model = fit_variogram(vario)

        # Block center
        block_center = (4.0, 4.0)
        block_centers = [block_center]

        # Block kriging
        block_result = block_kriging(z, coords, block_centers, model;
                                     block_size=2.0, n_grid=5)

        # Point kriging at the same center
        point_result = ordinary_kriging(z, coords, ([4.0], [4.0]), model)

        block_var = block_result.variances[1]
        point_var = point_result.variances[1]

        # Core property: averaging reduces variance
        @test block_var < point_var "Block variance should be < point variance"
        @test block_var / point_var > 0.1 "Variance reduction should be moderate (not degenerate)"
    end

    # =========================================================================
    # Test 4: Larger blocks have smaller variances (averaging effect)
    # =========================================================================
    @testset "Larger blocks have smaller variances (variance reduction)" begin
        Random.seed!(42)

        n = 35
        coords_x = rand(0:10, n)
        coords_y = rand(0:10, n)
        coords = (coords_x, coords_y)
        z = randn(n) .+ coords_x

        vario = empirical_variogram(coords, z; lags=9, maxlag=5.5)
        model = fit_variogram(vario)

        block_centers = [(5.0, 5.0)]

        # Small block (1.0)
        result_small = block_kriging(z, coords, block_centers, model;
                                     block_size=1.0, n_grid=5)

        # Medium block (3.0)
        result_medium = block_kriging(z, coords, block_centers, model;
                                      block_size=3.0, n_grid=5)

        # Large block (5.0)
        result_large = block_kriging(z, coords, block_centers, model;
                                     block_size=5.0, n_grid=5)

        var_small = result_small.variances[1]
        var_medium = result_medium.variances[1]
        var_large = result_large.variances[1]

        # Larger blocks should have smaller variances
        @test var_medium < var_small "Medium block variance should be smaller than small"
        @test var_large < var_medium "Large block variance should be smaller than medium"
    end

    # =========================================================================
    # Test 5: Numerical grid integration convergence
    # =========================================================================
    @testset "Higher n_grid produces more stable predictions (convergence)" begin
        Random.seed!(42)

        n = 30
        coords_x = rand(0:8, n)
        coords_y = rand(0:8, n)
        coords = (coords_x, coords_y)
        z = randn(n) .+ coords_x .* coords_y

        vario = empirical_variogram(coords, z; lags=8, maxlag=4.5)
        model = fit_variogram(vario)

        block_centers = [(4.0, 4.0)]

        # Coarse grid (3×3)
        result_coarse = block_kriging(z, coords, block_centers, model;
                                      block_size=2.0, n_grid=3)

        # Medium grid (5×5)
        result_medium = block_kriging(z, coords, block_centers, model;
                                      block_size=2.0, n_grid=5)

        # Fine grid (7×7)
        result_fine = block_kriging(z, coords, block_centers, model;
                                    block_size=2.0, n_grid=7)

        # Predictions should converge (finer grids are more accurate)
        pred_coarse = result_coarse.predictions[1]
        pred_medium = result_medium.predictions[1]
        pred_fine = result_fine.predictions[1]

        # All should be valid
        @test !isnan(pred_coarse) && !isnan(pred_medium) && !isnan(pred_fine)

        # Finer grids should give similar predictions (convergence)
        diff_coarse_medium = abs(pred_coarse - pred_medium)
        diff_medium_fine = abs(pred_medium - pred_fine)

        @test diff_medium_fine < diff_coarse_medium "Finer grids should converge"
    end

    # =========================================================================
    # Test 6: block_grid_points generates correct grid
    # =========================================================================
    @testset "block_grid_points generates interior points within block" begin
        # Create grid for block at (5, 5) with size 2.0
        grid_coords = block_grid_points((5.0, 5.0), 2.0, 5)

        x_coords = grid_coords[1]
        y_coords = grid_coords[2]

        # Should have 5×5 = 25 points
        @test length(x_coords) == 25 "Should have 25 grid points for 5×5 grid"
        @test length(y_coords) == 25 "Should have 25 grid points for 5×5 grid"

        # All points should be within block bounds
        block_min = 5.0 - 1.0
        block_max = 5.0 + 1.0

        @test all(x_coords .>= block_min) "X coords should be >= block_min"
        @test all(x_coords .<= block_max) "X coords should be <= block_max"
        @test all(y_coords .>= block_min) "Y coords should be >= block_min"
        @test all(y_coords .<= block_max) "Y coords should be <= block_max"
    end

    # =========================================================================
    # Test 7: Block kriging with local neighborhood
    # =========================================================================
    @testset "Block kriging respects n_neighbors parameter" begin
        Random.seed!(42)

        n = 50
        coords_x = rand(0:12, n)
        coords_y = rand(0:12, n)
        coords = (coords_x, coords_y)
        z = randn(n) .+ coords_x

        vario = empirical_variogram(coords, z; lags=10, maxlag=6.0)
        model = fit_variogram(vario)

        block_centers = [(6.0, 6.0)]

        # Block kriging with all neighbors
        result_all = block_kriging(z, coords, block_centers, model;
                                   block_size=3.0, n_neighbors=50)

        # Block kriging with limited neighbors
        result_local = block_kriging(z, coords, block_centers, model;
                                     block_size=3.0, n_neighbors=10)

        # Both should produce valid results (may differ due to neighborhood)
        @test !isnan(result_all.predictions[1])
        @test !isnan(result_local.predictions[1])

        # Predictions should be similar but not identical
        diff = abs(result_all.predictions[1] - result_local.predictions[1])
        @test diff < 5.0 "Local and global predictions should be similar"
    end

    # =========================================================================
    # Test 8: Block cross-validation with single block
    # =========================================================================
    @testset "block_cross_validate works with single block" begin
        Random.seed!(42)

        n = 25
        coords_x = rand(0:10, n)
        coords_y = rand(0:10, n)
        coords = (coords_x, coords_y)
        z = randn(n) .+ coords_x

        vario = empirical_variogram(coords, z; lags=8, maxlag=5.0)
        model = fit_variogram(vario)

        # Single block
        blocks = [(5.0, 5.0)]

        cv_result = block_cross_validate(z, coords, blocks, model;
                                         block_size=3.0, n_neighbors=15)

        @test haskey(cv_result, "rmse") "CV result should have RMSE"
        @test haskey(cv_result, "mae") "CV result should have MAE"
        @test haskey(cv_result, "predictions") "CV result should have predictions"
        @test cv_result["rmse"] > 0 "RMSE should be positive"
    end

    # =========================================================================
    # Test 9: Block cross-validation with multiple blocks
    # =========================================================================
    @testset "block_cross_validate on multiple blocks accumulates metrics" begin
        Random.seed!(42)

        n = 40
        coords_x = rand(0:12, n)
        coords_y = rand(0:12, n)
        coords = (coords_x, coords_y)
        z = randn(n) .+ coords_x .+ coords_y

        vario = empirical_variogram(coords, z; lags=10, maxlag=6.0)
        model = fit_variogram(vario)

        # Multiple blocks
        blocks = [
            (3.0, 3.0), (9.0, 3.0),
            (3.0, 9.0), (9.0, 9.0)
        ]

        cv_result = block_cross_validate(z, coords, blocks, model;
                                         block_size=4.0, n_neighbors=15)

        @test cv_result["rmse"] > 0 "RMSE should be positive"
        @test cv_result["mae"] > 0 "MAE should be positive"
        @test length(cv_result["residuals"]) == 4 "Should have 4 residuals"
        @test !any(isnan.(cv_result["residuals"])) "Residuals should be finite"
    end

    # =========================================================================
    # Test 10: Block kriging result structure
    # =========================================================================
    @testset "block_kriging result has all required fields" begin
        Random.seed!(42)

        n = 20
        coords_x = rand(0:8, n)
        coords_y = rand(0:8, n)
        coords = (coords_x, coords_y)
        z = randn(n)

        vario = empirical_variogram(coords, z; lags=6, maxlag=4.0)
        model = fit_variogram(vario)

        block_centers = [(4.0, 4.0)]
        result = block_kriging(z, coords, block_centers, model; block_size=2.0)

        # KrigingResult structure
        @test haskey(result, :predictions) "Result should have predictions"
        @test haskey(result, :variances) "Result should have variances"
        @test haskey(result, :weights) "Result should have weights"
        @test isa(result, KrigingResult) "Result should be KrigingResult type"
    end

    # =========================================================================
    # Test 11: Block kriging on real-world scale (county blocks)
    # =========================================================================
    @testset "Block kriging scales to county-sized blocks" begin
        Random.seed!(42)

        # Simulate provider density data across a region
        # Blocks are roughly county-sized (~50 km × 50 km)
        n = 100
        coords_x = rand(0:200, n)  # Region 200×200 km
        coords_y = rand(0:200, n)
        coords = (coords_x, coords_y)
        z = rand(n) .* 10  # Provider counts (0-10 per point)

        vario = empirical_variogram(coords, z; lags=20, maxlag=100.0)
        model = fit_variogram(vario)

        # 4 county-sized blocks (50 km each, spaced 100 km apart)
        block_centers = [
            (50.0, 50.0), (150.0, 50.0),
            (50.0, 150.0), (150.0, 150.0)
        ]

        result = block_kriging(z, coords, block_centers, model;
                              block_size=50.0, n_grid=7)

        @test length(result.predictions) == 4 "Should have predictions for 4 counties"
        @test all(>=(0), result.predictions) "County predictions should be non-negative"
        @test !any(isnan.(result.predictions)) "Predictions should be finite"
    end

    # =========================================================================
    # Test 12: Block kriging variance is positive and bounded
    # =========================================================================
    @testset "Block kriging variances are valid and bounded" begin
        Random.seed!(42)

        n = 30
        coords_x = rand(0:10, n)
        coords_y = rand(0:10, n)
        coords = (coords_x, coords_y)
        z = randn(n)

        vario = empirical_variogram(coords, z; lags=8, maxlag=5.5)
        model = fit_variogram(vario)

        block_centers = [(5.0, 5.0), (7.0, 3.0), (3.0, 7.0)]
        result = block_kriging(z, coords, block_centers, model; block_size=2.0, n_grid=5)

        # All variances should be positive and bounded
        @test all(>=(0), result.variances) "Variances must be non-negative"
        @test all(<=(10.0), result.variances) "Variances must be reasonable (<10)"
    end

end
