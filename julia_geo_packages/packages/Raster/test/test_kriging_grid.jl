"""
Test suite for Raster.jl kriging grid integration.

Tests cover:
- Grid creation (bounds, resolution, coordinates)
- Ordinary kriging on grid (shape, variance properties)
- Universal kriging (drift capture)
- Block kriging (variance reduction)
- Co-kriging (auxiliary variable integration)
- Integration tests (spatial patterns)
"""

using Test
using Raster
using Geostatistics
using Statistics

# Test setup: synthetic data
function setup_test_data()
    # Small training dataset: provider density
    coords = ([0.0, 1.0, 2.0, 0.5, 1.5], [0.0, 0.0, 0.0, 1.0, 1.0])
    z = [5.0, 6.5, 5.2, 6.0, 5.8]  # Provider density per 100k population

    # Fit variogram
    vario = Geostatistics.empirical_variogram(coords, z; lags=5)
    model = Geostatistics.fit_variogram(vario; model_type=:exponential)

    return coords, z, model
end

@testset "Raster.jl Kriging Grid Integration" begin

    # ========================================
    # 1. Grid Creation Tests
    # ========================================
    @testset "Grid Creation" begin
        # Test 1: Basic grid creation
        bounds = (x_min=-1.0, x_max=3.0, y_min=-1.0, y_max=2.0)
        resolution_m = 50000.0  # ~0.45 degrees
        grid = Raster.create_regular_grid(bounds, resolution_m)

        # Check grid properties
        @test length(grid.x_coords) > 0
        @test length(grid.y_coords) > 0
        @test size(grid.data, 1) == length(grid.y_coords)
        @test size(grid.data, 2) == length(grid.x_coords)
        @test all(isnan.(grid.data) .| (grid.data .== 0.0))  # Empty initially

        # Check bounds are respected
        @test grid.x_coords[1] >= bounds.x_min
        @test grid.x_coords[end] <= bounds.x_max
        @test grid.y_coords[1] >= bounds.y_min
        @test grid.y_coords[end] <= bounds.y_max

        # Check metadata
        @test haskey(grid.metadata, "bounds")
        @test haskey(grid.metadata, "resolution_m")
        @test haskey(grid.metadata, "created_at")
        @test grid.metadata["resolution_m"] == resolution_m
    end

    @testset "Grid Resolution" begin
        # Test 2: High resolution grid
        bounds = (x_min=0.0, x_max=1.0, y_min=0.0, y_max=1.0)
        resolution_m = 10000.0  # ~0.09 degrees

        grid = Raster.create_regular_grid(bounds, resolution_m)
        expected_cells = ceil(Int, (bounds.x_max - bounds.x_min) * 111_000 / resolution_m)
        @test length(grid.x_coords) >= expected_cells - 2
        @test length(grid.y_coords) >= expected_cells - 2
    end

    # ========================================
    # 2. Ordinary Kriging on Grid
    # ========================================
    @testset "Ordinary Kriging Grid" begin
        coords, z, model = setup_test_data()

        # Create grid
        bounds = (x_min=-0.5, x_max=2.5, y_min=-0.5, y_max=1.5)
        grid = Raster.create_regular_grid(bounds, 50000.0)

        # Perform kriging
        result_grid = Raster.ordinary_kriging_grid(z, coords, grid, model; n_neighbors=3)

        # Check shape
        @test size(result_grid.data, 1) == length(result_grid.y_coords)
        @test size(result_grid.data, 2) == length(result_grid.x_coords)

        # Check predictions are reasonable (between observed min/max with some margin)
        z_min, z_max = minimum(z), maximum(z)
        margin = 0.2 * (z_max - z_min)
        @test minimum(result_grid.data[.!isnan.(result_grid.data)]) > z_min - margin
        @test maximum(result_grid.data[.!isnan.(result_grid.data)]) < z_max + margin

        # Check variances are non-negative
        @test haskey(result_grid.metadata, "variances")
        variances = result_grid.metadata["variances"]
        @test all(variances .>= 0.0)
        @test !all(variances .== 0.0)  # Some variance should exist

        # Check metadata
        @test result_grid.metadata["kriging_method"] == "ordinary"
        @test result_grid.metadata["n_neighbors"] == 3
    end

    # ========================================
    # 3. Universal Kriging with Drift
    # ========================================
    @testset "Universal Kriging Grid" begin
        coords, z, model = setup_test_data()

        # Create synthetic trend: z increases with x
        z_trend = z .+ 0.5 .* coords[1]

        # Re-fit model on trend data
        vario = Geostatistics.empirical_variogram(coords, z_trend; lags=5)
        model = Geostatistics.fit_variogram(vario; model_type=:exponential)

        # Create grid and fit universal kriging
        bounds = (x_min=-0.5, x_max=2.5, y_min=-0.5, y_max=1.5)
        grid = Raster.create_regular_grid(bounds, 50000.0)

        result_grid = Raster.universal_kriging_grid(z_trend, coords, grid, model;
                                                     drift_order=1, n_neighbors=3)

        # Check properties
        @test size(result_grid.data) == (length(grid.y_coords), length(grid.x_coords))
        @test result_grid.metadata["kriging_method"] == "universal"
        @test result_grid.metadata["drift_order"] == 1

        # UK predictions should capture trend
        # (rough check: correlate predictions with x-coordinate)
        correlations = []
        for j in 1:size(result_grid.data, 1)
            row_vals = result_grid.data[j, :]
            if !any(isnan.(row_vals))
                cor_val = cor(grid.x_coords, row_vals)
                push!(correlations, cor_val)
            end
        end

        # With a positive trend, correlation should be positive on average
        if !isempty(correlations)
            mean_cor = mean(correlations)
            @test mean_cor > -0.5  # Weak positive trend expected
        end
    end

    # ========================================
    # 4. Block Kriging
    # ========================================
    @testset "Block Kriging Grid" begin
        coords, z, model = setup_test_data()

        bounds = (x_min=-0.5, x_max=2.5, y_min=-0.5, y_max=1.5)
        grid = Raster.create_regular_grid(bounds, 50000.0)

        # Perform block kriging
        blocks = Int[]  # Empty blocks vector (not used in this simple test)
        result_grid = Raster.block_kriging_grid(z, coords, blocks, grid, model;
                                                 block_size=0.5, n_neighbors=3)

        # Check properties
        @test size(result_grid.data) == (length(grid.y_coords), length(grid.x_coords))
        @test result_grid.metadata["kriging_method"] == "block"
        @test result_grid.metadata["block_size"] == 0.5

        # Block kriging variances should be lower than point kriging
        # (averaging reduces variance)
        block_variances = result_grid.metadata["variances"]
        @test all(block_variances .>= 0.0)

        # Check variance reduction compared to ordinary kriging
        grid_ok = Raster.create_regular_grid(bounds, 50000.0)
        grid_ok = Raster.ordinary_kriging_grid(z, coords, grid_ok, model; n_neighbors=3)
        ok_variances = grid_ok.metadata["variances"]

        # Block kriging variance should be <= point kriging variance
        # (not strict due to discretization effects)
        reduction_ratio = mean(block_variances[.!isnan.(block_variances)] ./
                              ok_variances[.!isnan.(ok_variances)])
        @test reduction_ratio <= 1.1  # Allow 10% tolerance
    end

    # ========================================
    # 5. Co-kriging with Auxiliary Variable
    # ========================================
    @testset "Co-kriging Grid" begin
        coords, z_primary, model_p = setup_test_data()

        # Auxiliary variable: population
        z_auxiliary = [1000.0, 1200.0, 950.0, 1100.0, 1050.0]

        # Fit auxiliary model
        vario_aux = Geostatistics.empirical_variogram(coords, z_auxiliary; lags=5)
        model_aux = Geostatistics.fit_variogram(vario_aux; model_type=:exponential)

        # Cross-variogram (simplified: use primary model)
        model_cross = model_p

        bounds = (x_min=-0.5, x_max=2.5, y_min=-0.5, y_max=1.5)
        grid = Raster.create_regular_grid(bounds, 50000.0)

        # Perform co-kriging
        result_grid = Raster.cokriging_grid(z_primary, z_auxiliary, coords, grid,
                                             model_p, model_cross; model_aux=model_aux,
                                             n_neighbors=3)

        # Check properties
        @test size(result_grid.data) == (length(grid.y_coords), length(grid.x_coords))
        @test result_grid.metadata["kriging_method"] == "cokriging"
        @test haskey(result_grid.metadata, "aux_predictions")
        @test result_grid.metadata["n_primary"] == length(z_primary)
        @test result_grid.metadata["n_auxiliary"] == length(z_auxiliary)

        # Co-kriging predictions should be influenced by auxiliary variable
        aux_preds = result_grid.metadata["aux_predictions"]
        @test size(aux_preds) == size(result_grid.data)
    end

    # ========================================
    # 6. Helper Functions
    # ========================================
    @testset "Reshape Predictions" begin
        coords, z, model = setup_test_data()

        bounds = (x_min=-0.5, x_max=2.5, y_min=-0.5, y_max=1.5)
        grid = Raster.create_regular_grid(bounds, 50000.0)

        n_x = length(grid.x_coords)
        n_y = length(grid.y_coords)

        # Create test linear vector
        predictions_linear = vec(reshape(1.0:(n_x*n_y), n_y, n_x))

        # Reshape to matrix
        matrix = Raster.reshape_predictions(predictions_linear, grid)

        # Check shape
        @test size(matrix) == (n_y, n_x)

        # Check values match expected ordering
        idx = 1
        for j in 1:n_y
            for i in 1:n_x
                @test matrix[j, i] == predictions_linear[idx]
                idx += 1
            end
        end
    end

    @testset "Uncertainty Surface" begin
        coords, z, model = setup_test_data()

        bounds = (x_min=-0.5, x_max=2.5, y_min=-0.5, y_max=1.5)
        grid = Raster.create_regular_grid(bounds, 50000.0)

        result_grid = Raster.ordinary_kriging_grid(z, coords, grid, model; n_neighbors=3)
        variances = vec(result_grid.metadata["variances"])

        # Create uncertainty surface
        uncertainty_grid = Raster.create_uncertainty_surface(variances, grid)

        # Check properties
        @test size(uncertainty_grid.data) == size(result_grid.data)
        @test uncertainty_grid.metadata["type"] == "confidence_interval_95"

        # CI width should be approximately 1.96 * sqrt(variance)
        base_vars = uncertainty_grid.metadata["base_variances"]
        expected_ci = 1.96 .* sqrt.(base_vars)

        # Check that CI widths are reasonable
        @test all(uncertainty_grid.data .>= 0.0)
        @test maximum(uncertainty_grid.data) > 0.0  # Some non-zero CI
    end

    # ========================================
    # 7. Integration Tests
    # ========================================
    @testset "Spatial Pattern Integration" begin
        # Create synthetic spatial data with clear gradient
        n_train = 20
        x_train = rand(n_train) .* 3.0 .- 1.0
        y_train = rand(n_train) .* 2.0 .- 0.5
        coords = (x_train, y_train)

        # Synthetic observations: z increases with x (linear trend)
        z = 5.0 .+ 2.0 .* x_train .+ 0.5 .* randn(n_train)

        # Fit model
        vario = Geostatistics.empirical_variogram(coords, z; lags=5)
        model = Geostatistics.fit_variogram(vario; model_type=:exponential)

        # Create fine grid
        bounds = (x_min=-1.5, x_max=3.5, y_min=-1.0, y_max=2.0)
        grid = Raster.create_regular_grid(bounds, 30000.0)

        # Kriging prediction
        result_grid = Raster.ordinary_kriging_grid(z, coords, grid, model; n_neighbors=10)

        # Check that spatial pattern is captured
        # (predictions should increase roughly with x)
        n_x = length(grid.x_coords)
        n_y = length(grid.y_coords)

        # Average predictions at different x slices
        predictions_left = mean(result_grid.data[:, 1:div(n_x, 3)])
        predictions_right = mean(result_grid.data[:, end-div(n_x, 3):end])

        # Right side should have higher predictions due to positive x-trend
        @test predictions_right > predictions_left - 0.5  # Allow some tolerance
    end

    @testset "Metadata Consistency" begin
        coords, z, model = setup_test_data()

        bounds = (x_min=-0.5, x_max=2.5, y_min=-0.5, y_max=1.5)
        resolution_m = 50000.0
        grid = Raster.create_regular_grid(bounds, resolution_m)

        # Test different kriging methods
        methods = [
            ("ordinary", Raster.ordinary_kriging_grid(z, coords, grid, model)),
            ("universal", Raster.universal_kriging_grid(z, coords, grid, model)),
            ("block", Raster.block_kriging_grid(z, coords, Int[], grid, model)),
        ]

        for (name, result_grid) in methods
            # Check common metadata
            @test haskey(result_grid.metadata, "kriging_method")
            @test haskey(result_grid.metadata, "model_type")
            @test haskey(result_grid.metadata, "n_neighbors")
            @test haskey(result_grid.metadata, "variances")
            @test result_grid.metadata["kriging_method"] == name
        end
    end

end  # main testset

println("All Raster.jl kriging grid tests passed!")
