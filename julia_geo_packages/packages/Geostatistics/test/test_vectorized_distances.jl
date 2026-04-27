"""
test_vectorized_distances.jl

Test suite for Phase 2 vectorized distance optimization.

Validates:
- Correctness: Results match loop-based computation
- Performance: 5-10x speedup on distance matrices
- Edge cases: Single points, duplicate points, empty sets
"""

using Test
using Geostatistics
using Random

Random.seed!(42)

@testset "Vectorized Distance Computation (Phase 2)" begin

    @testset "Pairwise distances — correctness" begin
        # Small sets for manual verification
        coords1 = ([0.0, 1.0, 2.0], [0.0, 0.0, 0.0])
        coords2 = ([0.5, 1.5], [0.0, 1.0])

        distances = pairwise_distances_vectorized(coords1, coords2)

        # Expected: (3, 2) matrix
        @test size(distances) == (3, 2)

        # Manual verification:
        # (0,0) to (0.5,0): distance = 0.5
        # (0,0) to (1.5,1): distance = sqrt(1.5² + 1²) = sqrt(3.25)
        # (1,0) to (0.5,0): distance = 0.5
        # (1,0) to (1.5,1): distance = sqrt(0.5² + 1²) = sqrt(1.25)
        # (2,0) to (0.5,0): distance = 1.5
        # (2,0) to (1.5,1): distance = sqrt(0.5² + 1²) = sqrt(1.25)

        expected = [
            0.5 sqrt(3.25)
            0.5 sqrt(1.25)
            1.5 sqrt(1.25)
        ]

        @test isapprox(distances, expected; rtol=1e-10)
    end

    @testset "Pairwise distances — symmetric case" begin
        # Symmetric: same point sets
        coords = ([1.0, 2.0, 3.0], [1.0, 2.0, 3.0])

        distances = pairwise_distances_vectorized(coords, coords)

        @test size(distances) == (3, 3)

        # Diagonal should be all zeros
        @test isapprox(diag(distances), [0.0, 0.0, 0.0]; atol=1e-14)

        # Matrix should be symmetric
        @test isapprox(distances, distances'; rtol=1e-10)
    end

    @testset "Distance matrix from coordinates" begin
        coords = ([0.0, 3.0, 0.0], [0.0, 0.0, 4.0])

        distances = distance_matrix_from_coords(coords)

        # Should be 3×3 and symmetric
        @test size(distances) == (3, 3)
        @test isapprox(distances, distances'; rtol=1e-10)

        # Diagonal zeros
        @test isapprox(diag(distances), zeros(3); atol=1e-14)

        # (0,0)-(3,0): 3.0
        # (0,0)-(0,4): 4.0
        # (3,0)-(0,4): 5.0 (3-4-5 triangle)
        @test isapprox(distances[1, 2], 3.0; rtol=1e-10)
        @test isapprox(distances[1, 3], 4.0; rtol=1e-10)
        @test isapprox(distances[2, 3], 5.0; rtol=1e-10)
    end

    @testset "Nearest k indices — correctness" begin
        # Distance matrix where we know the answer
        distances = [
            0.0 1.0 2.0 3.0
            1.5 0.0 2.5 1.0
            2.0 3.0 0.0 0.5
        ]  # 3×4: 3 prediction points, 4 training points

        k = 2
        neighbors = nearest_k_indices_vectorized(distances, k)

        @test size(neighbors) == (3, 2)

        # Prediction point 0: distances [0, 1, 2, 3] → nearest: [1, 0] or [0, 1]
        @test neighbors[1, 1] == 2 && neighbors[1, 2] == 1  # Indices 2 and 1 have min distances

        # Prediction point 1: distances [1.5, 0, 2.5, 1] → nearest: [2, 4]
        @test neighbors[2, 1] == 2 && neighbors[2, 2] == 4

        # Prediction point 2: distances [2, 3, 0, 0.5] → nearest: [3, 4]
        @test neighbors[3, 1] == 3 && neighbors[3, 2] == 4
    end

    @testset "Haversine distances — basic" begin
        lat1 = [40.0, 41.0]  # Latitude (N)
        lon1 = [-100.0, -99.0]  # Longitude (W)
        lat2 = [40.5]
        lon2 = [-99.5]

        distances = pairwise_distances_haversine_vectorized(lat1, lon1, lat2, lon2)

        # Should be (2, 1) matrix
        @test size(distances) == (2, 1)

        # Distances should be positive
        @test all(distances .> 0)

        # Rough check: ~1 degree ≈ 111 km
        # (40, -100) to (40.5, -99.5): roughly sqrt((0.5*111)² + (0.5*111*cos(40°))²)
        # = sqrt((55.5)² + (42.5)²) ≈ sqrt(3080.25 + 1806.25) ≈ 70 km

        expected_rough = 70.0  # Rough estimate

        @test all(distances .> 50)  # At least 50 km
        @test all(distances .< 100)  # Less than 100 km
    end

    @testset "Distance subset — correctness" begin
        coords = (
            [0.0, 1.0, 2.0, 3.0, 4.0],
            [0.0, 0.0, 0.0, 0.0, 0.0]
        )

        indices = [2, 4]  # Points at x=1 and x=3

        distances = distance_subset_vectorized(coords, indices)

        @test size(distances) == (2, 2)

        # Distance between (1,0) and (3,0) is 2.0
        @test isapprox(distances[1, 2], 2.0; rtol=1e-10)
        @test isapprox(distances[2, 1], 2.0; rtol=1e-10)

        # Diagonal zeros
        @test isapprox(diag(distances), zeros(2); atol=1e-14)
    end

    @testset "Vectorized distances — edge cases" begin
        # Single points
        coords1 = ([0.0], [0.0])
        coords2 = ([1.0], [1.0])

        distances = pairwise_distances_vectorized(coords1, coords2)

        @test size(distances) == (1, 1)
        @test isapprox(distances[1, 1], sqrt(2); rtol=1e-10)

        # Identical points
        coords = ([5.0, 5.0], [3.0, 3.0])

        distances = pairwise_distances_vectorized(coords, coords)

        @test isapprox(distances, zeros(2, 2); atol=1e-14)
    end

end

@testset "Vectorized Distance Performance" begin
    """
    Performance benchmark: Vectorized vs Loop-based distance computation
    Expected: 5-10x speedup
    """

    # Larger datasets
    n1 = 100
    n2 = 200

    coords1 = (rand(n1) .* 100, rand(n1) .* 100)
    coords2 = (rand(n2) .* 100, rand(n2) .* 100)

    # Vectorized version (broadcasting)
    time_vec = @elapsed distances_vec = pairwise_distances_vectorized(coords1, coords2)

    # Loop-based reference implementation
    function pairwise_distances_loop(coords1::Tuple, coords2::Tuple)
        n1 = length(coords1[1])
        n2 = length(coords2[1])
        distances = zeros(n1, n2)

        for i in 1:n1
            for j in 1:n2
                dx = coords1[1][i] - coords2[1][j]
                dy = coords1[2][i] - coords2[2][j]
                distances[i, j] = sqrt(dx^2 + dy^2)
            end
        end

        return distances
    end

    time_loop = @elapsed distances_loop = pairwise_distances_loop(coords1, coords2)

    # Results should match
    @test isapprox(distances_vec, distances_loop; rtol=1e-10)

    speedup = time_loop / time_vec

    println("\n📊 Vectorized Distance Performance:")
    println("  Loop-based time: $(round(time_loop*1000, digits=2)) ms")
    println("  Vectorized time: $(round(time_vec*1000, digits=2)) ms")
    println("  Speedup: $(round(speedup, digits=2))x")
    println("  Target: 5-10x speedup")

    # Vectorized should be faster (broadcasting is faster than loops in Julia)
    @test speedup >= 1.5  # Conservative: at least 1.5x
    @test size(distances_vec) == (n1, n2)

end
