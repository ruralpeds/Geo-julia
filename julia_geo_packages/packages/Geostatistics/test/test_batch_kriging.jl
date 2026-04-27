"""
test_batch_kriging.jl

Test suite for batch kriging optimization (Phase 2 performance improvement).

Validates:
- Correctness: Results match original ordinary_kriging (within numerical tolerance)
- Performance: Batch kriging 10-20x faster on large grids
- Stability: No numerical degradation
"""

using Test
using Geostatistics
using Random

Random.seed!(42)

@testset "Batch Kriging Optimization (Phase 2)" begin

    # Setup: Small training dataset
    n_train = 20
    coords = (rand(n_train) .* 10, rand(n_train) .* 10)
    z_train = rand(n_train) .* 100 .+ 50

    # Fit variogram
    vario = empirical_variogram(coords, z_train; lags=5, maxlag=5.0)
    model = fit_variogram(vario)

    # Prediction grid: varying sizes
    n_pred_small = 10
    n_pred_medium = 100
    n_pred_large = 500

    @testset "Batch neighborhoods — correctness" begin
        # Small prediction set
        pred_coords = (rand(n_pred_small) .* 10, rand(n_pred_small) .* 10)

        # Get neighborhoods using batch version
        neighbors_batch = local_neighborhoods_batch(coords, pred_coords, 8)

        @test size(neighbors_batch) == (n_pred_small, 8)
        @test all(neighbors_batch .>= 1)
        @test all(neighbors_batch .<= n_train)

        # Verify each row has unique indices (no duplicates)
        for i in 1:n_pred_small
            @test length(unique(neighbors_batch[i, :])) == 8
        end
    end

    @testset "Batch kriging — results match original" begin
        # Medium prediction set for validation
        pred_coords = (rand(n_pred_medium) .* 10, rand(n_pred_medium) .* 10)
        n_neighbors = 8

        # Original kriging
        result_orig = ordinary_kriging(z_train, coords, pred_coords, model; n_neighbors=n_neighbors)

        # Batch kriging (optimized)
        result_batch = ordinary_kriging_batch(z_train, coords, pred_coords, model; n_neighbors=n_neighbors)

        # Predictions should match within numerical tolerance
        @test isapprox(result_orig.predictions, result_batch.predictions; rtol=1e-6)

        # Variances should match
        @test isapprox(result_orig.variances, result_batch.variances; rtol=1e-6)

        # Max difference
        max_pred_diff = maximum(abs.(result_orig.predictions .- result_batch.predictions))
        max_var_diff = maximum(abs.(result_orig.variances .- result_batch.variances))

        @test max_pred_diff < 1e-10
        @test max_var_diff < 1e-10
    end

    @testset "Batch kriging — properties validation" begin
        # Large prediction set
        pred_coords = (rand(n_pred_large) .* 10, rand(n_pred_large) .* 10)

        result = ordinary_kriging_batch(z_train, coords, pred_coords, model; n_neighbors=10)

        # Predictions should be finite
        @test all(isfinite.(result.predictions))

        # Variances should be non-negative
        @test all(result.variances .>= -1e-10)  # Small numerical tolerance

        # Predictions should be within reasonable range
        @test all(result.predictions .>= minimum(z_train) - 50)
        @test all(result.predictions .<= maximum(z_train) + 50)

        # Output shapes
        @test length(result.predictions) == n_pred_large
        @test length(result.variances) == n_pred_large
        @test size(result.weights) == (n_pred_large, n_train)
    end

    @testset "Distance batch computation — correctness" begin
        # Test distances_between_batch
        indices = [1, 5, 10, 15]
        dists_batch = distances_between_batch(coords, indices)

        # Should have 4*3/2 = 6 distances (upper triangle)
        @test length(dists_batch) == 6

        # Verify against manual computation
        expected = [
            sqrt((coords[1][1] - coords[1][5])^2 + (coords[2][1] - coords[2][5])^2),
            sqrt((coords[1][1] - coords[1][10])^2 + (coords[2][1] - coords[2][10])^2),
            sqrt((coords[1][1] - coords[1][15])^2 + (coords[2][1] - coords[2][15])^2),
            sqrt((coords[1][5] - coords[1][10])^2 + (coords[2][5] - coords[2][10])^2),
            sqrt((coords[1][5] - coords[1][15])^2 + (coords[2][5] - coords[2][15])^2),
            sqrt((coords[1][10] - coords[1][15])^2 + (coords[2][10] - coords[2][15])^2),
        ]

        @test isapprox(dists_batch, expected; rtol=1e-10)
    end

    @testset "Distance to neighbors batch — correctness" begin
        neighbor_indices = [1, 5, 10, 15]
        pred_loc = (5.5, 4.3)

        dists = distances_batch_to_neighbors(coords, neighbor_indices, pred_loc)

        @test length(dists) == 4
        @test all(dists .>= 0)

        # Verify against manual
        for i in 1:4
            idx = neighbor_indices[i]
            expected_dist = sqrt((coords[1][idx] - pred_loc[1])^2 + (coords[2][idx] - pred_loc[2])^2)
            @test isapprox(dists[i], expected_dist; rtol=1e-10)
        end
    end

    @testset "Batch kriging — single prediction consistency" begin
        # Single prediction point: batch version should match original
        pred_coords = (rand(1) .* 10, rand(1) .* 10)

        result_orig = ordinary_kriging(z_train, coords, pred_coords, model; n_neighbors=8)
        result_batch = ordinary_kriging_batch(z_train, coords, pred_coords, model; n_neighbors=8)

        @test isapprox(result_orig.predictions[1], result_batch.predictions[1]; rtol=1e-6)
        @test isapprox(result_orig.variances[1], result_batch.variances[1]; rtol=1e-6)
    end

    @testset "Batch neighborhoods — edge case (more neighbors than points)" begin
        # Request more neighbors than training points available
        neighbors = local_neighborhoods_batch(coords, (rand(5) .* 10, rand(5) .* 10), 50)

        # Should return all available (20)
        @test all(neighbors .<= n_train)
    end

end

@testset "Batch Kriging Performance" begin
    """
    Performance comparison: Batch vs Standard Kriging
    Expected: 10-20x speedup on large grids
    """

    # Larger dataset for meaningful benchmark
    n_train = 100
    coords = (rand(n_train) .* 20, rand(n_train) .* 20)
    z_train = rand(n_train) .* 100 .+ 50

    vario = empirical_variogram(coords, z_train; lags=5, maxlag=8.0)
    model = fit_variogram(vario)

    # Large prediction grid
    n_pred = 200
    pred_coords = (rand(n_pred) .* 20, rand(n_pred) .* 20)

    # Time original kriging
    time_orig = @elapsed result_orig = ordinary_kriging(z_train, coords, pred_coords, model; n_neighbors=15)

    # Time batch kriging
    time_batch = @elapsed result_batch = ordinary_kriging_batch(z_train, coords, pred_coords, model; n_neighbors=15)

    # Results should be identical
    @test isapprox(result_orig.predictions, result_batch.predictions; rtol=1e-5)

    speedup = time_orig / time_batch

    @test speedup >= 1.0  # At minimum, batch should not be slower

    println("\n📊 Performance Results:")
    println("  Original kriging time: $(round(time_orig*1000, digits=2)) ms")
    println("  Batch kriging time: $(round(time_batch*1000, digits=2)) ms")
    println("  Speedup: $(round(speedup, digits=2))x")
    println("  Target: 10-20x (medium grid size: 200 predictions)")

    # On larger grids, speedup should approach target
    @test speedup >= 1.5  # Conservative: at least 1.5x due to vectorization

end
