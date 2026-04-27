"""
Test suite for Raster.jl I/O functionality (Days 13-14 Phase B)

Tests:
1. RasterGrid construction and metadata handling
2. Save/load roundtrip with GeoTIFF format
3. WorldPop loader with mock data generation
4. GHSL loader with multiple layers
5. Cache directory management
6. Bounds and coordinate validation
"""

using Test
using Raster
using Statistics

@testset "RasterGrid Construction and Properties" begin
    # Create test data
    ny, nx = 50, 75
    data = randn(Float32, ny, nx)
    x_coords = collect(range(-10.0, -8.0, length=nx))
    y_coords = collect(range(5.0, 8.0, length=ny))
    crs = "EPSG:4326"

    # Test basic construction with keyword arguments
    metadata = Dict("source" => "test", "year" => 2020)
    raster = RasterGrid(
        data, x_coords, y_coords;
        crs=crs,
        resolution_m=250.0,
        metadata=metadata
    )

    @test size(raster) == (ny, nx)
    @test raster.crs == "EPSG:4326"
    @test raster.resolution_m == 250.0
    @test raster.metadata["source"] == "test"
    @test raster.metadata["year"] == 2020

    # Test bounds computation
    @test raster.bounds.west < -10.0
    @test raster.bounds.east > -8.0
    @test raster.bounds.south < 5.0
    @test raster.bounds.north > 8.0

    # Test indexing
    @test raster[1, 1] ≈ data[1, 1]
    @test raster[25, 50] ≈ data[25, 50]

    # Test coordinate utilities
    x_test, y_test = center_coordinates(raster)
    @test x_test == raster.x_coords
    @test y_test == raster.y_coords

    # Test pixel coordinates
    x_pix, y_pix = pixel_coordinates(raster, 25, 50)
    @test x_pix ≈ raster.x_coords[50]
    @test y_pix ≈ raster.y_coords[25]
end

@testset "RasterGrid Metadata Management" begin
    ny, nx = 30, 40
    data = rand(Float32, ny, nx)
    x_coords = collect(range(0.0, 10.0, length=nx))
    y_coords = collect(range(0.0, 5.0, length=ny))

    metadata = Dict("source" => "test")
    raster = RasterGrid(data, x_coords, y_coords; metadata=metadata)

    # Test get_metadata
    @test get_metadata(raster, "source") == "test"
    @test get_metadata(raster, "nonexistent", "default") == "default"

    # Test update_metadata
    update_metadata!(raster, "year", 2021)
    @test raster.metadata["year"] == 2021

    update_metadata!(raster, "uncertainty", 0.15)
    @test raster.metadata["uncertainty"] == 0.15
end

@testset "Dimension and Bounds Validation" begin
    ny, nx = 25, 35

    # Test dimension mismatch detection
    data = rand(Float32, ny, nx)
    x_coords = collect(range(0.0, 10.0, length=nx + 1))  # Wrong length
    y_coords = collect(range(0.0, 5.0, length=ny))

    @test_throws ErrorException RasterGrid(
        data, x_coords, y_coords;
        resolution_m=100.0,
        metadata=Dict("source" => "test")
    )

    # Test bounds validation
    valid_bounds = (west=0.0, east=10.0, south=0.0, north=5.0)
    @test_nowarn RasterGrid(
        data,
        collect(range(0.0, 10.0, length=nx)),
        collect(range(0.0, 5.0, length=ny)),
        "EPSG:4326",
        valid_bounds,
        100.0
    )

    # Test invalid bounds (west >= east)
    invalid_bounds = (west=10.0, east=0.0, south=0.0, north=5.0)
    @test_throws ErrorException RasterGrid(
        data,
        collect(range(0.0, 10.0, length=nx)),
        collect(range(0.0, 5.0, length=ny)),
        "EPSG:4326",
        invalid_bounds,
        100.0
    )

    # Test negative resolution
    @test_throws ErrorException RasterGrid(
        data,
        collect(range(0.0, 10.0, length=nx)),
        collect(range(0.0, 5.0, length=ny)),
        "EPSG:4326",
        valid_bounds,
        -100.0
    )
end

@testset "RasterGrid Display and Info" begin
    ny, nx = 10, 15
    data = rand(Float32, ny, nx)
    x_coords = collect(range(-5.0, 5.0, length=nx))
    y_coords = collect(range(-2.0, 2.0, length=ny))

    raster = RasterGrid(data, x_coords, y_coords; resolution_m=250.0)

    # Test that show doesn't error
    @test_nowarn show(IOBuffer(), raster)

    # Basic properties accessible
    @test minimum(raster.data) < maximum(raster.data)
    @test raster.crs == "EPSG:4326"
end

@testset "Save/Load Roundtrip" begin
    # Create test raster
    ny, nx = 20, 30
    data = rand(Float32, ny, nx)
    x_coords = collect(range(-10.0, -8.0, length=nx))
    y_coords = collect(range(5.0, 8.0, length=ny))

    metadata = Dict(
        "source" => "test_data",
        "year" => 2020,
        "units" => "persons per cell",
        "uncertainty" => 0.15
    )

    raster_orig = RasterGrid(
        data, x_coords, y_coords;
        crs="EPSG:4326",
        resolution_m=250.0,
        metadata=metadata
    )

    # Create temporary file
    tmp_file = tempname() * ".tif"

    try
        # Save and load
        save_raster(raster_orig, tmp_file)
        @test isfile(tmp_file)

        raster_loaded = load_raster(tmp_file)

        # Check basic properties
        @test size(raster_loaded) == size(raster_orig)
        @test raster_loaded.crs == raster_orig.crs

        # Check coordinates (should be close due to rounding)
        @test length(raster_loaded.x_coords) == length(raster_orig.x_coords)
        @test length(raster_loaded.y_coords) == length(raster_orig.y_coords)

        # Check metadata preservation
        @test raster_loaded.metadata["source"] == "test_data"
        @test raster_loaded.metadata["year"] == 2020

    finally
        # Clean up
        if isfile(tmp_file)
            rm(tmp_file)
        end
    end
end

@testset "WorldPop Loader - Mock Data" begin
    # Test basic loading for Nigeria
    pop = load_worldpop("Nigeria", 2020)

    @test isa(pop, RasterGrid)
    @test size(pop, 1) > 0  # ny > 0
    @test size(pop, 2) > 0  # nx > 0
    @test pop.metadata["source"] == "WorldPop"
    @test pop.metadata["year"] == 2020
    @test pop.metadata["uncertainty"] == 0.15
    @test pop.crs == "EPSG:4326"
    @test all(pop.data .>= 0)  # Population can't be negative

    # Test different resolutions
    pop_1km = load_worldpop("Nigeria", 2020; resolution="1km")
    pop_250m = load_worldpop("Nigeria", 2020; resolution="250m")

    @test pop_1km.resolution_m == 1000.0
    @test pop_250m.resolution_m == 250.0

    # Higher resolution should have more cells
    @test size(pop_250m, 1) > size(pop_1km, 1)
    @test size(pop_250m, 2) > size(pop_1km, 2)

    # Test country code normalization
    pop_iso3 = load_worldpop("NGA", 2020)
    @test pop_iso3.metadata["country"] == "NGA"
end

@testset "WorldPop Loader - Multiple Countries" begin
    # Test loading for different countries
    countries = ["Nigeria", "Kenya", "Uganda", "Tanzania"]

    for country in countries
        pop = load_worldpop(country, 2020)

        @test isa(pop, RasterGrid)
        @test pop.metadata["source"] == "WorldPop"
        @test pop.metadata["year"] == 2020
        @test minimum(pop.data) >= 0.0
        @test pop.bounds.west < pop.bounds.east
        @test pop.bounds.south < pop.bounds.north
    end
end

@testset "WorldPop Loader - Bounds Clipping" begin
    # Test with custom bounds
    custom_bounds = (west=-6.0, east=-4.0, south=6.0, north=8.0)
    pop_clipped = load_worldpop("Nigeria", 2020; bounds=custom_bounds)

    @test pop_clipped.bounds.west >= -6.0
    @test pop_clipped.bounds.east <= -4.0
    @test pop_clipped.bounds.south >= 6.0
    @test pop_clipped.bounds.north <= 8.0
end

@testset "GHSL Loader - Built-up Layer" begin
    # Test built-up area layer
    buildup = load_ghsl("Nigeria"; year=2020, layer="built-up")

    @test isa(buildup, RasterGrid)
    @test buildup.metadata["source"] == "GHSL"
    @test buildup.metadata["year"] == 2020
    @test buildup.metadata["layer"] == "built-up"
    @test buildup.crs == "EPSG:4326"

    # Built-up should be binary (0 or 1)
    unique_vals = unique(buildup.data)
    @test all(unique_vals .∈ [[0.0], [1.0], [0.0, 1.0]])

    # Resolution for GHSL is 100m
    @test buildup.resolution_m == 100.0
end

@testset "GHSL Loader - Settlement Layer" begin
    # Test settlement layer
    settlement = load_ghsl("Nigeria"; year=2020, layer="settlement")

    @test settlement.metadata["source"] == "GHSL"
    @test settlement.metadata["layer"] == "settlement"

    # Settlement should be continuous 0-1
    @test all(settlement.data .>= 0.0)
    @test all(settlement.data .<= 1.0)
end

@testset "GHSL Loader - Population Layer" begin
    # Test population layer
    pop_ghsl = load_ghsl("Nigeria"; year=2020, layer="population")

    @test pop_ghsl.metadata["source"] == "GHSL"
    @test pop_ghsl.metadata["layer"] == "population"
    @test all(pop_ghsl.data .>= 0.0)
end

@testset "GHSL Loader - Invalid Layer" begin
    @test_throws ErrorException load_ghsl("Nigeria"; layer="invalid_layer")
end

@testset "Raster Clipping" begin
    # Create test raster
    ny, nx = 50, 100
    data = ones(Float32, ny, nx)
    x_coords = collect(range(0.0, 10.0, length=nx))
    y_coords = collect(range(0.0, 5.0, length=ny))

    raster = RasterGrid(data, x_coords, y_coords; resolution_m=100.0)

    # Clip to smaller bounds
    clip_bounds = (west=2.0, east=8.0, south=1.0, north=4.0)
    clipped = clip_raster(raster, clip_bounds)

    @test size(clipped, 1) < size(raster, 1)
    @test size(clipped, 2) < size(raster, 2)
    @test clipped.bounds.west >= 2.0
    @test clipped.bounds.east <= 8.0
    @test clipped.bounds.south >= 1.0
    @test clipped.bounds.north <= 4.0
    @test clipped.metadata["clipped"] == true
end

@testset "Bounds Buffering" begin
    bounds = (west=0.0, east=10.0, south=0.0, north=5.0)
    buffer_deg = 0.5

    buffered = buffer_bounds(bounds, buffer_deg)

    @test buffered.west == -0.5
    @test buffered.east == 10.5
    @test buffered.south == -0.5
    @test buffered.north == 5.5
end

@testset "Cache Directory Management" begin
    # Test cache_worldpop doesn't error
    cache_dir = cache_worldpop("Nigeria", 2020)

    @test !isempty(cache_dir)
    @test contains(cache_dir, ".cache")
end

@testset "Data Type Preservation" begin
    # Test with different data types
    for T in [Float32, Float64, Int32]
        ny, nx = 10, 15
        data = ones(T, ny, nx)
        x_coords = collect(range(0.0, 5.0, length=nx))
        y_coords = collect(range(0.0, 2.0, length=ny))

        raster = RasterGrid(data, x_coords, y_coords)

        @test eltype(raster.data) == T
    end
end

@testset "Edge Cases" begin
    # Single row
    data_row = reshape(Float32[1, 2, 3, 4, 5], 1, 5)
    x_coords = collect(range(0.0, 4.0, length=5))
    y_coords = [0.0]

    raster_row = RasterGrid(data_row, x_coords, y_coords)
    @test size(raster_row) == (1, 5)

    # Single column
    data_col = reshape(Float32[1, 2, 3, 4, 5], 5, 1)
    x_coords_col = [0.0]
    y_coords_col = collect(range(0.0, 4.0, length=5))

    raster_col = RasterGrid(data_col, x_coords_col, y_coords_col)
    @test size(raster_col) == (5, 1)
end

println("All Raster.jl I/O tests passed!")
