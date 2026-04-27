"""
test_validation.jl

Tests for raster validation and quality assessment (Days 14-15 Phase D).
- Test cross-validation metrics (RMSE, MAE, correlation)
- Test inter-source agreement computation
- Test fusion quality report
- Test high-agreement cells have low uncertainty
"""

using Test
using Statistics

# Note: Tests run after Raster module is loaded in runtests.jl

@testset "Inter-Source Agreement" begin
    x = collect(0:0.1:3)
    y = collect(0:0.1:3)
    n_y, n_x = length(y), length(x)

    # Create three population sources with different agreement levels
    true_data = rand(n_y, n_x) .* 1000

    # Source 1: True data + small noise (high stability)
    data1 = true_data .+ randn(n_y, n_x) .* 10

    # Source 2: True data + small noise (high stability)
    data2 = true_data .+ randn(n_y, n_x) .* 10

    # Source 3: True data + large noise (low stability)
    data3 = true_data .+ randn(n_y, n_x) .* 100

    bounds = (west=0.0, east=3.0, south=0.0, north=3.0)
    grid1 = RasterGrid(data1, x, y, "EPSG:4326", bounds, 100.0)
    grid2 = RasterGrid(data2, x, y, "EPSG:4326", bounds, 100.0)
    grid3 = RasterGrid(data3, x, y, "EPSG:4326", bounds, 100.0)

    @testset "Agreement matrix computation" begin
        agreement = inter_source_agreement([grid1, grid2, grid3])
        @test size(agreement) == size(grid1)
        @test !isempty(agreement.data)
    end

    @testset "Low agreement when sources differ" begin
        # Grids with high disagreement
        data_a = ones(n_y, n_x) .* 100
        data_b = ones(n_y, n_x) .* 500

        grid_a = RasterGrid(data_a, x, y, "EPSG:4326", bounds, 100.0)
        grid_b = RasterGrid(data_b, x, y, "EPSG:4326", bounds, 100.0)

        agreement = inter_source_agreement([grid_a, grid_b])
        std_vals = vec(agreement.data)
        valid_std = filter(!isnan, std_vals)

        # Should have high std (high disagreement)
        @test mean(valid_std) > 100
    end

    @testset "High agreement when sources agree" begin
        # Identical grids
        agreement = inter_source_agreement([grid1, grid1])
        std_vals = vec(agreement.data)
        valid_std = filter(!isnan, std_vals)

        # Should have std ≈ 0 (perfect agreement)
        @test all(valid_std .< 1e-10)
    end

    @testset "Requires at least 2 sources" begin
        @test_throws ArgumentError inter_source_agreement([grid1])
    end

    @testset "Returns same bounds as input" begin
        agreement = inter_source_agreement([grid1, grid2])
        @test agreement.bounds == grid1.bounds
        @test agreement.crs == grid1.crs
    end
end

@testset "Cross-Validation" begin
    x = collect(0:0.1:5)
    y = collect(0:0.1:5)
    n_y, n_x = length(y), length(x)

    # Create synthetic population grids
    data1 = ones(n_y, n_x) .* 100 .+ randn(n_y, n_x) .* 5
    data2 = ones(n_y, n_x) .* 105 .+ randn(n_y, n_x) .* 8

    bounds = (west=0.0, east=5.0, south=0.0, north=5.0)
    grid1 = RasterGrid(data1, x, y, "EPSG:4326", bounds, 100.0)
    grid2 = RasterGrid(data2, x, y, "EPSG:4326", bounds, 100.0)

    # Create validation points (5 random locations)
    val_x = [0.5, 1.5, 2.5, 3.5, 4.5]
    val_y = [0.5, 1.5, 2.5, 3.5, 4.5]
    # Create synthetic "ground truth" near the mean of sources
    val_obs = ones(5) .* 102.5

    @testset "Basic cross-validation" begin
        results = raster_cross_validate([grid1, grid2], (val_x, val_y), val_obs)

        @test haskey(results, "rmse")
        @test haskey(results, "mae")
        @test haskey(results, "agreement")
        @test results["source_count"] == 2
        @test results["validation_points"] == 5
    end

    @testset "RMSE and MAE are non-negative" begin
        results = raster_cross_validate([grid1, grid2], (val_x, val_y), val_obs)

        rmse_vals = values(results["rmse"])
        mae_vals = values(results["mae"])

        for rmse in rmse_vals
            if !isnan(rmse)
                @test rmse >= 0
            end
        end

        for mae in mae_vals
            if !isnan(mae)
                @test mae >= 0
            end
        end
    end

    @testset "Correlation matrix is square" begin
        results = raster_cross_validate([grid1, grid2], (val_x, val_y), val_obs)
        agreement_matrix = results["agreement"]
        n_sources = results["source_count"]
        @test size(agreement_matrix) == (n_sources, n_sources)
    end

    @testset "Diagonal of correlation is 1.0" begin
        results = raster_cross_validate([grid1, grid2], (val_x, val_y), val_obs)
        agreement_matrix = results["agreement"]

        for i in 1:size(agreement_matrix, 1)
            @test agreement_matrix[i, i] ≈ 1.0 atol=1e-10
        end
    end

    @testset "Throws on mismatched input dimensions" begin
        @test_throws DimensionMismatch raster_cross_validate(
            [grid1, grid2],
            (val_x, val_y),
            [100.0]  # Wrong length
        )
    end
end

@testset "Fusion Quality Report" begin
    x = collect(0:0.1:4)
    y = collect(0:0.1:4)
    n_y, n_x = length(y), length(x)

    # Create sources with controlled agreement
    data_base = ones(n_y, n_x) .* 1000

    # High-agreement region: all sources similar
    data1 = copy(data_base) .+ randn(n_y, n_x) .* 10
    data2 = copy(data_base) .+ randn(n_y, n_x) .* 10

    # Low-agreement region: sources differ significantly
    data1[1:10, 1:10] = copy(data_base[1:10, 1:10]) .* 2
    data2[1:10, 1:10] = copy(data_base[1:10, 1:10]) .* 0.5

    bounds = (west=0.0, east=4.0, south=0.0, north=4.0)
    grid1 = RasterGrid(data1, x, y, "EPSG:4326", bounds, 100.0)
    grid2 = RasterGrid(data2, x, y, "EPSG:4326", bounds, 100.0)

    sources = Dict("Source1" => grid1, "Source2" => grid2)
    fused = fuse_population_sources(sources)

    @testset "Quality report structure" begin
        quality = fusion_quality_report(fused, sources)

        @test haskey(quality, "cv")
        @test haskey(quality, "confidence")
        @test haskey(quality, "mean_confidence")
        @test haskey(quality, "high_confidence_fraction")
        @test haskey(quality, "low_confidence_cells")
    end

    @testset "CV matrix has correct shape" begin
        quality = fusion_quality_report(fused, sources)
        @test size(quality["cv"]) == size(fused)
        @test size(quality["confidence"]) == size(fused)
    end

    @testset "Confidence in valid range [0, 1]" begin
        quality = fusion_quality_report(fused, sources)
        conf_vals = filter(!isnan, vec(quality["confidence"]))

        if !isempty(conf_vals)
            @test all(conf_vals .>= 0.0)
            @test all(conf_vals .<= 1.0)
        end
    end

    @testset "Mean confidence is in [0, 1]" begin
        quality = fusion_quality_report(fused, sources)
        mean_conf = quality["mean_confidence"]

        if !isnan(mean_conf)
            @test 0.0 <= mean_conf <= 1.0
        end
    end

    @testset "High confidence fraction in [0, 1]" begin
        quality = fusion_quality_report(fused, sources)
        high_conf_frac = quality["high_confidence_fraction"]

        if !isnan(high_conf_frac)
            @test 0.0 <= high_conf_frac <= 1.0
        end
    end

    @testset "Low confidence cells identified correctly" begin
        quality = fusion_quality_report(fused, sources)
        low_conf_cells = quality["low_confidence_cells"]

        for idx in low_conf_cells
            @test quality["confidence"][idx] < 0.5
        end
    end

    @testset "High-agreement sources have high confidence" begin
        # Create perfectly agreeing sources
        sources_agree = Dict("S1" => grid1, "S2" => grid1)  # Same data
        fused_agree = fuse_population_sources(sources_agree)
        quality_agree = fusion_quality_report(fused_agree, sources_agree)

        valid_conf = filter(!isnan, vec(quality_agree["confidence"]))
        if !isempty(valid_conf)
            @test mean(valid_conf) > 0.95  # Very high agreement
        end
    end

    @testset "Divergent sources have low confidence in divergent regions" begin
        quality = fusion_quality_report(fused, sources)

        # Low-agreement region should have many low-confidence cells
        low_conf_in_region = sum([
            quality["confidence"][i, j] < 0.5
            for i in 1:10, j in 1:10
        ])

        high_conf_in_region = sum([
            quality["confidence"][i, j] > 0.8
            for i in 1:10, j in 1:10
        ])

        # Low-agreement region should have more low-conf than high-conf
        @test low_conf_in_region >= high_conf_in_region
    end
end

@testset "Integration: Fusion → Validation → Quality" begin
    """
    End-to-end test: create sources, fuse, validate, assess quality.
    Verifies that high-agreement sources produce high-confidence fusions.
    """
    x = collect(0:0.1:2)
    y = collect(0:0.1:2)

    # Create highly correlated sources
    true_pop = ones(length(y), length(x)) .* 500
    data1 = true_pop .+ randn(length(y), length(x)) .* 5
    data2 = true_pop .+ randn(length(y), length(x)) .* 5

    bounds = (west=0.0, east=2.0, south=0.0, north=2.0)
    grid1 = RasterGrid(data1, x, y, "EPSG:4326", bounds, 100.0)
    grid2 = RasterGrid(data2, x, y, "EPSG:4326", bounds, 100.0)

    sources = Dict("Grid1" => grid1, "Grid2" => grid2)

    # Fuse
    fused = fuse_population_sources(sources)

    # Assess quality
    quality = fusion_quality_report(fused, sources)

    @testset "Highly-correlated sources → high confidence" begin
        mean_conf = quality["mean_confidence"]
        @test mean_conf > 0.80  # Should be confident
    end

    @testset "Fused estimates near source means for agreeing sources" begin
        valid_cells = .!isnan.(fused.data)
        fused_vals = fused.data[valid_cells]
        grid1_vals = grid1.data[valid_cells]
        grid2_vals = grid2.data[valid_cells]

        expected_fused = (grid1_vals .+ grid2_vals) ./ 2
        @test mean(abs.(fused_vals .- expected_fused)) < 1e-6
    end
end
