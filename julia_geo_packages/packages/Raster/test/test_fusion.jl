"""
test_fusion.jl

Tests for population source fusion (Days 14-15 Phase D).
- Test Bayesian fusion with weights summing to 1.0
- Test uncertainty combination (non-negative)
- Test grid alignment (coordinate compatibility)
- Test source weighting estimation
"""

using Test
using Statistics

# Note: Tests run after Raster module is loaded in runtests.jl

@testset "Grid Alignment" begin
    # Create test grids with different resolutions
    x1 = collect(0:0.2:5)
    y1 = collect(0:0.2:5)
    data1 = rand(length(y1), length(x1))

    x2 = collect(0:0.5:5)
    y2 = collect(0:0.5:5)
    data2 = rand(length(y2), length(x2))

    bounds1 = (west=0.0, east=5.0, south=0.0, north=5.0)
    bounds2 = (west=0.0, east=5.0, south=0.0, north=5.0)

    grid1 = RasterGrid(data1, x1, y1, "EPSG:4326", bounds1, 200.0)
    grid2 = RasterGrid(data2, x2, y2, "EPSG:4326", bounds2, 500.0)

    @testset "Alignment to common grid" begin
        aligned = align_raster_grids([grid1, grid2])

        @test length(aligned) == 2
        @test size(aligned[1]) == size(aligned[2])
        @test aligned[1].x_coords == aligned[2].x_coords
        @test aligned[1].y_coords == aligned[2].y_coords
    end

    @testset "Finest resolution is preserved" begin
        aligned = align_raster_grids([grid1, grid2])
        @test aligned[1].resolution_m ≈ 200.0
    end

    @testset "Single grid returns copy" begin
        aligned = align_raster_grids([grid1])
        @test length(aligned) == 1
        @test size(aligned[1]) == size(grid1)
    end
end

@testset "Source Weight Estimation" begin
    # Create test grids with different stability
    x = collect(0:0.1:5)
    y = collect(0:0.1:5)

    # Stable source (low CV)
    data_stable = ones(length(y), length(x)) .* 100 .+ randn(length(y), length(x)) .* 5

    # Noisy source (high CV)
    data_noisy = ones(length(y), length(x)) .* 100 .+ randn(length(y), length(x)) .* 30

    bounds = (west=0.0, east=5.0, south=0.0, north=5.0)
    grid_stable = RasterGrid(data_stable, x, y, "EPSG:4326", bounds, 100.0)
    grid_noisy = RasterGrid(data_noisy, x, y, "EPSG:4326", bounds, 100.0)

    @testset "Weights sum to 1.0" begin
        weights = estimate_source_weights([grid_stable, grid_noisy])
        @test sum(values(weights)) ≈ 1.0 atol=1e-10
    end

    @testset "Stable source gets higher weight" begin
        weights = estimate_source_weights([grid_stable, grid_noisy])
        w_stable = weights["source_1"]
        w_noisy = weights["source_2"]
        @test w_stable > w_noisy
    end

    @testset "Single source returns unit weight" begin
        weights = estimate_source_weights([grid_stable])
        @test weights["source_1"] ≈ 1.0
    end

    @testset "Equal sources get equal weights" begin
        weights = estimate_source_weights([grid_stable, grid_stable])
        w1 = weights["source_1"]
        w2 = weights["source_2"]
        @test w1 ≈ w2 ≈ 0.5 atol=1e-10
    end
end

@testset "Population Fusion" begin
    x = collect(0:0.2:5)
    y = collect(0:0.2:5)
    n_y, n_x = length(y), length(x)

    # Create two population sources
    data1 = rand(n_y, n_x) .* 1000
    data2 = rand(n_y, n_x) .* 1000

    bounds = (west=0.0, east=5.0, south=0.0, north=5.0)
    grid1 = RasterGrid(data1, x, y, "EPSG:4326", bounds, 200.0,
                      Dict("source" => "WorldPop"))
    grid2 = RasterGrid(data2, x, y, "EPSG:4326", bounds, 200.0,
                      Dict("source" => "GHSL"))

    sources = Dict("WorldPop" => grid1, "GHSL" => grid2)

    @testset "Basic fusion" begin
        fused = fuse_population_sources(sources)
        @test size(fused) == size(grid1)
        @test !isempty(fused.data)
    end

    @testset "Weights are tracked in metadata" begin
        fused = fuse_population_sources(sources)
        @test haskey(fused.metadata, "source_weights")
        weights = fused.metadata["source_weights"]
        @test sum(values(weights)) ≈ 1.0
    end

    @testset "Uncertainty surface is included" begin
        fused = fuse_population_sources(sources)
        @test haskey(fused.metadata, "uncertainty")
        uncertainty = fused.metadata["uncertainty"]
        @test size(uncertainty) == size(fused)
    end

    @testset "Custom weights are respected" begin
        custom_weights = Dict("WorldPop" => 0.7, "GHSL" => 0.3)
        fused = fuse_population_sources(sources; weights=custom_weights)
        metadata_weights = fused.metadata["source_weights"]
        @test metadata_weights["WorldPop"] ≈ 0.7 atol=1e-10
        @test metadata_weights["GHSL"] ≈ 0.3 atol=1e-10
    end

    @testset "Uncertainty is non-negative" begin
        fused = fuse_population_sources(sources)
        uncertainty = fused.metadata["uncertainty"]
        valid_unc = filter(!isnan, vec(uncertainty))
        @test all(valid_unc .>= 0.0)
    end

    @testset "Fused values are within source range (mostly)" begin
        fused = fuse_population_sources(sources)

        # For each cell, fused should be between (or near) min and max of sources
        for i in 1:n_y, j in 1:n_x
            v1, v2 = grid1[i, j], grid2[i, j]
            vf = fused[i, j]

            if !isnan(v1) && !isnan(v2) && !isnan(vf)
                v_min = min(v1, v2)
                v_max = max(v1, v2)
                # Allow small deviation due to weighted average
                @test v_min - 1e-6 <= vf <= v_max + 1e-6
            end
        end
    end

    @testset "Metadata tracks source information" begin
        fused = fuse_population_sources(sources)
        @test fused.metadata["n_sources"] == 2
        @test "WorldPop" in fused.metadata["source_names"]
        @test "GHSL" in fused.metadata["source_names"]
        @test fused.metadata["fusion_method"] == "Bayesian weighted average"
    end

    @testset "Missing source in weights throws error" begin
        bad_weights = Dict("WorldPop" => 0.5)  # Missing GHSL
        @test_throws ArgumentError fuse_population_sources(sources; weights=bad_weights)
    end

    @testset "Empty sources throws error" begin
        @test_throws ArgumentError fuse_population_sources(Dict())
    end
end

@testset "Fusion with NaN values" begin
    x = collect(0:0.2:2)
    y = collect(0:0.2:2)
    n_y, n_x = length(y), length(x)

    # Create grids with some NaN values
    data1 = rand(n_y, n_x) .* 1000
    data2 = rand(n_y, n_x) .* 1000

    data1[1, 1] = NaN
    data2[2, 2] = NaN

    bounds = (west=0.0, east=2.0, south=0.0, north=2.0)
    grid1 = RasterGrid(data1, x, y, "EPSG:4326", bounds, 200.0)
    grid2 = RasterGrid(data2, x, y, "EPSG:4326", bounds, 200.0)

    sources = Dict("Source1" => grid1, "Source2" => grid2)

    @testset "NaN propagation" begin
        fused = fuse_population_sources(sources)

        # Cell with both NaN should be NaN
        @test isnan(fused[1, 1])

        # Cell with one NaN should use the other
        @test !isnan(fused[2, 2])
        @test fused[2, 2] ≈ grid1[2, 2]
    end
end
