"""
Comprehensive tests for spatial analysis operations.

Tests all spatial operations including buffer, intersect, union, clip,
dissolve, reproject, and statistical analysis functions.
"""

using Test
using GeoSpatialEngine
using DataFrames
using Dates

# Helper function to create test data
function create_test_data(n_points::Int=10)::GeoSpatialData
    lats = rand(40.0:0.1:42.0, n_points)
    lons = rand(-74.0:-0.1:-72.0, n_points)
    values = rand(1:100, n_points)

    df = DataFrame(
        latitude = lats,
        longitude = lons,
        temperature = values,
        country = repeat(["USA", "Canada"], n_points ÷ 2)
    )

    return GeoSpatialData(df; crs="EPSG:4326")
end

@testset "Spatial Operations Tests" begin

    @testset "Buffer Operation" begin
        data = create_test_data(5)

        # Test positive buffer
        buffered = buffer(data, 100.0; units="meters")
        @test isa(buffered, GeoSpatialData)
        @test nrow(buffered.data) == nrow(data.data)
        @test haskey(buffered.data, :buffer_distance)
        @test buffered.data[1, :buffer_distance] == 100.0

        # Test negative buffer (shrink)
        shrunk = buffer(data, -50.0; units="meters")
        @test isa(shrunk, GeoSpatialData)
        @test nrow(shrunk.data) > 0

        # Test with kilometers
        buffered_km = buffer(data, 0.1; units="kilometers")
        @test isa(buffered_km, GeoSpatialData)
    end

    @testset "Buffer with Empty Data" begin
        empty_data = GeoSpatialData(DataFrame())
        buffered = buffer(empty_data, 100.0)
        @test nrow(buffered.data) == 0
    end

    @testset "Intersect Operation" begin
        data1 = create_test_data(5)
        data2 = create_test_data(5)

        # Test intersection
        intersection = intersect(data1, data2)
        @test isa(intersection, GeoSpatialData)
        @test haskey(intersection.metadata, "operation")
        @test intersection.metadata["operation"] == "intersect"
    end

    @testset "Intersect with Empty Data" begin
        empty_data = GeoSpatialData(DataFrame())
        data = create_test_data(5)

        result = intersect(empty_data, data)
        @test nrow(result.data) == 0

        result2 = intersect(data, empty_data)
        @test nrow(result2.data) == 0
    end

    @testset "Union Operation" begin
        data1 = create_test_data(3)
        data2 = create_test_data(3)

        union_result = union(data1, data2)
        @test isa(union_result, GeoSpatialData)
        @test nrow(union_result.data) >= nrow(data1.data)
        @test haskey(union_result.metadata, "operation")
        @test union_result.metadata["operation"] == "union"
    end

    @testset "Clip Operation" begin
        data = create_test_data(20)

        # Create bounds
        bounds = (minx=-73.5, miny=40.5, maxx=-72.5, maxy=41.5)

        clipped = clip(data, bounds)
        @test isa(clipped, GeoSpatialData)
        @test haskey(clipped.metadata, "operation")
        @test clipped.metadata["operation"] == "clip"

        # Verify all clipped points are within bounds
        if nrow(clipped.data) > 0
            @test all(clipped.data[!, :longitude] .>= bounds.minx)
            @test all(clipped.data[!, :longitude] .<= bounds.maxx)
            @test all(clipped.data[!, :latitude] .>= bounds.miny)
            @test all(clipped.data[!, :latitude] .<= bounds.maxy)
        end
    end

    @testset "Clip with Invalid Bounds" begin
        data = create_test_data(5)
        invalid_bounds = (minx=0.0, miny=0.0, maxx=-1.0, maxy=-1.0)  # invalid

        result = clip(data, invalid_bounds)
        @test nrow(result.data) == 0
    end

    @testset "Dissolve Operation" begin
        data = create_test_data(10)

        dissolved = dissolve(data, "country")
        @test isa(dissolved, GeoSpatialData)
        @test haskey(dissolved.metadata, "operation")
        @test dissolved.metadata["operation"] == "dissolve"
        @test haskey(dissolved.data, :merged_count)
    end

    @testset "Dissolve with Invalid Column" begin
        data = create_test_data(5)

        result = dissolve(data, "nonexistent_column")
        @test nrow(result.data) == 0
    end

    @testset "Reproject Operation" begin
        data = create_test_data(5)

        # Reproject to Web Mercator
        reprojected = reproject(data, "EPSG:3857")
        @test isa(reprojected, GeoSpatialData)
        @test reprojected.crs == "EPSG:3857"

        # Reproject back to WGS84
        back_to_wgs = reproject(reprojected, "EPSG:4326")
        @test back_to_wgs.crs == "EPSG:4326"
    end

    @testset "Reproject Same CRS" begin
        data = create_test_data(5)

        same_crs = reproject(data, "EPSG:4326")
        @test same_crs.crs == "EPSG:4326"
    end

    @testset "Spatial Autocorrelation" begin
        data = create_test_data(10)

        morans_i = spatial_autocorrelation(data, "temperature")
        @test isa(morans_i, Float64)
        @test morans_i >= -1.0 && morans_i <= 1.0
    end

    @testset "Spatial Autocorrelation with Few Points" begin
        data = create_test_data(2)

        result = spatial_autocorrelation(data, "temperature")
        @test isa(result, Float64)
    end

    @testset "Hotspot Analysis" begin
        data = create_test_data(15)

        hotspots = hotspot_analysis(data, "temperature")
        @test isa(hotspots, GeoSpatialData)
        @test haskey(hotspots.data, :hotspot_z_score)
        @test haskey(hotspots.data, :hotspot_classification)

        # Check for valid classifications
        classifications = unique(hotspots.data[!, :hotspot_classification])
        @test all(c in ["Hotspot", "Coldspot", "Not Significant"] for c in classifications)
    end

    @testset "Hotspot Analysis with Few Points" begin
        data = create_test_data(2)

        result = hotspot_analysis(data, "temperature")
        @test nrow(result.data) >= 0
    end

    @testset "Cluster Analysis" begin
        data = create_test_data(15)

        clusters = cluster_analysis(data; n_clusters=3)
        @test isa(clusters, GeoSpatialData)
        @test haskey(clusters.data, :cluster_id)
        @test haskey(clusters.data, :distance_to_centroid)

        # Check cluster assignments
        unique_clusters = unique(clusters.data[!, :cluster_id])
        @test length(unique_clusters) <= 3
    end

    @testset "Cluster Analysis with Few Points" begin
        data = create_test_data(2)

        result = cluster_analysis(data; n_clusters=2)
        @test nrow(result.data) == 2
    end

    @testset "Kriging Interpolation" begin
        data = create_test_data(10)

        kriged = kriging_interpolation(data, "temperature")
        @test isa(kriged, GeoSpatialData)
        @test haskey(kriged.data, :kriged_value)
        @test haskey(kriged.data, :kriging_variance)
        @test haskey(kriged.data, :kriging_se)
    end

    @testset "Kriging with Few Points" begin
        data = create_test_data(2)

        result = kriging_interpolation(data, "temperature")
        @test nrow(result.data) >= 0
    end

    @testset "Haversine Distance" begin
        # NYC to Boston (roughly 215 km)
        dist = GeoSpatialEngine.haversine_distance(40.7128, -74.0060, 42.3601, -71.0589)

        @test dist > 200000  # > 200 km
        @test dist < 230000  # < 230 km
    end

    @testset "Compute Bounds" begin
        data = create_test_data(5)

        bounds = GeoSpatialEngine.compute_bounds(data)
        @test haskey(bounds, :minx)
        @test haskey(bounds, :miny)
        @test haskey(bounds, :maxx)
        @test haskey(bounds, :maxy)

        @test bounds.minx <= bounds.maxx
        @test bounds.miny <= bounds.maxy
    end

    @testset "Compute Bounds - Empty Data" begin
        empty_data = GeoSpatialData(DataFrame())

        bounds = GeoSpatialEngine.compute_bounds(empty_data)
        @test bounds.minx == 0.0
        @test bounds.miny == 0.0
    end

    @testset "Find Overlapping Features" begin
        data = create_test_data(10)
        bounds = (minx=-73.5, miny=40.5, maxx=-72.5, maxy=41.5)

        overlapping = GeoSpatialEngine.find_overlapping_features(data, bounds)
        @test isa(overlapping, Vector)
        @test all(x > 0 for x in overlapping)
    end

    @testset "Chained Operations" begin
        data = create_test_data(20)

        # Clip → Buffer → Cluster
        bounds = (minx=-73.5, miny=40.5, maxx=-72.5, maxy=41.5)
        clipped = clip(data, bounds)

        if nrow(clipped.data) > 0
            buffered = buffer(clipped, 50.0)
            @test isa(buffered, GeoSpatialData)
            @test nrow(buffered.data) > 0
        end
    end

end

println("\n✅ Spatial Operations Tests Completed")
