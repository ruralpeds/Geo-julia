"""
Visualization Module Tests

Tests for:
- Interactive web maps
- Heatmap rendering
- 3D visualizations
- Time-series animations
- GeoJSON/GeoTIFF export
- Dashboard creation
- Result publishing
"""

using Test
using DataFrames
using Dates
using GeoSpatialEngine

@testset "Visualization Module" begin

    # Create sample data for testing
    function create_test_geospatial_data()
        df = DataFrame(
            latitude=[40.7128, 40.7580, 40.8566, 40.6892],
            longitude=[-74.0060, -73.9855, -74.2090, -74.0445],
            temperature=[20.5, 22.1, 18.9, 21.3],
            humidity=[65.0, 70.0, 55.0, 68.0],
            name=["Manhattan", "Central Park", "Bronx", "Brooklyn"],
            timestamp=[DateTime(2024, 1, 1, 12, 0, 0),
                      DateTime(2024, 1, 1, 13, 0, 0),
                      DateTime(2024, 1, 1, 14, 0, 0),
                      DateTime(2024, 1, 1, 15, 0, 0)]
        )

        metadata = Dict(
            "source" => "test_data",
            "region" => "New York",
            "unit" => "Celsius"
        )

        return GeoSpatialData(
            df,
            metadata,
            "POINT",
            "EPSG:4326",
            (minx=-74.3, miny=40.5, maxx=-73.7, maxy=41.0),
            nothing
        )
    end

    # ========================================================================
    # Web Map Tests
    # ========================================================================

    @testset "Web Maps" begin

        @test begin
            data = create_test_geospatial_data()
            map = create_web_map(data; title="Test Map")
            map isa InteractiveMap
        end

        @test begin
            data = create_test_geospatial_data()
            map = create_web_map(data; title="NYC Points", basemap="OpenStreetMap")
            !isempty(map.html) && contains(map.html, "leaflet")
        end

        @test begin
            data = create_test_geospatial_data()
            map = create_web_map(data)
            map.config.center_lat ≈ 40.75 atol=0.1
        end

        @test begin
            data = create_test_geospatial_data()
            map = create_web_map(data)
            2 <= map.config.zoom <= 15  # Reasonable zoom level
        end

        # Test error handling: empty data
        @test_throws ErrorException begin
            empty_df = DataFrame(latitude=[], longitude=[])
            empty_data = GeoSpatialData(
                empty_df, Dict(), "POINT", "EPSG:4326",
                (minx=0, miny=0, maxx=0, maxy=0), nothing
            )
            create_web_map(empty_data)
        end

        # Test error handling: missing coordinates
        @test_throws ErrorException begin
            bad_df = DataFrame(name=["A", "B"], value=[1, 2])
            bad_data = GeoSpatialData(
                bad_df, Dict(), "POINT", "EPSG:4326",
                (minx=0, miny=0, maxx=1, maxy=1), nothing
            )
            create_web_map(bad_data)
        end
    end

    # ========================================================================
    # Heatmap Tests
    # ========================================================================

    @testset "Heatmaps" begin

        @test begin
            data = create_test_geospatial_data()
            heatmap = render_heatmap(data, "temperature")
            heatmap isa InteractiveMap
        end

        @test begin
            data = create_test_geospatial_data()
            heatmap = render_heatmap(data, "temperature"; colormap="YlOrRd")
            !isempty(heatmap.html)
        end

        @test begin
            data = create_test_geospatial_data()
            heatmap = render_heatmap(data, "humidity"; colormap="viridis")
            heatmap.config.title == "Heatmap: humidity"
        end

        @test begin
            data = create_test_geospatial_data()
            heatmap = render_heatmap(data, "temperature")
            length(heatmap.layers) > 0
        end

        # Test error handling: empty data
        @test_throws ErrorException begin
            empty_df = DataFrame(latitude=[], longitude=[])
            empty_data = GeoSpatialData(
                empty_df, Dict(), "POINT", "EPSG:4326",
                (minx=0, miny=0, maxx=0, maxy=0), nothing
            )
            render_heatmap(empty_data, "temperature")
        end

        # Test error handling: missing variable
        @test_throws ErrorException begin
            data = create_test_geospatial_data()
            render_heatmap(data, "nonexistent_column")
        end

        # Test error handling: missing coordinates
        @test_throws ErrorException begin
            bad_df = DataFrame(value=[1, 2, 3])
            bad_data = GeoSpatialData(
                bad_df, Dict(), "POINT", "EPSG:4326",
                (minx=0, miny=0, maxx=1, maxy=1), nothing
            )
            render_heatmap(bad_data, "value")
        end
    end

    # ========================================================================
    # 3D Visualization Tests
    # ========================================================================

    @testset "3D Visualizations" begin

        @test begin
            data = create_test_geospatial_data()
            viz = create_3d_visualization(data, "temperature")
            viz isa Dict
        end

        @test begin
            data = create_test_geospatial_data()
            viz = create_3d_visualization(data, "temperature")
            viz["type"] == "3d_points"
        end

        @test begin
            data = create_test_geospatial_data()
            viz = create_3d_visualization(data, "temperature"; color_variable="humidity")
            viz["color_variable"] == "humidity"
        end

        @test begin
            data = create_test_geospatial_data()
            viz = create_3d_visualization(data, "temperature")
            haskey(viz, "points") && length(viz["points"]) > 0
        end

        @test begin
            data = create_test_geospatial_data()
            viz = create_3d_visualization(data, "temperature")
            haskey(viz, "bounds")
        end

        # Test error handling: empty data
        @test_throws ErrorException begin
            empty_df = DataFrame(latitude=[], longitude=[])
            empty_data = GeoSpatialData(
                empty_df, Dict(), "POINT", "EPSG:4326",
                (minx=0, miny=0, maxx=0, maxy=0), nothing
            )
            create_3d_visualization(empty_data, "temperature")
        end

        # Test error handling: missing z variable
        @test_throws ErrorException begin
            data = create_test_geospatial_data()
            create_3d_visualization(data, "nonexistent")
        end

        # Test error handling: missing color variable
        @test_throws ErrorException begin
            data = create_test_geospatial_data()
            create_3d_visualization(data, "temperature"; color_variable="bad_col")
        end
    end

    # ========================================================================
    # Animation Tests
    # ========================================================================

    @testset "Time-Series Animations" begin

        @test begin
            data = create_test_geospatial_data()
            anim = animate_timeseries(data, "timestamp", "temperature")
            anim isa Dict
        end

        @test begin
            data = create_test_geospatial_data()
            anim = animate_timeseries(data, "timestamp", "temperature"; fps=10)
            anim["fps"] == 10
        end

        @test begin
            data = create_test_geospatial_data()
            anim = animate_timeseries(data, "timestamp", "temperature")
            anim["type"] == "animation"
        end

        @test begin
            data = create_test_geospatial_data()
            anim = animate_timeseries(data, "timestamp", "humidity")
            anim["value_column"] == "humidity"
        end

        @test begin
            data = create_test_geospatial_data()
            anim = animate_timeseries(data, "timestamp", "temperature")
            haskey(anim, "frames") && length(anim["frames"]) > 0
        end

        # Test error handling: empty data
        @test_throws ErrorException begin
            empty_df = DataFrame(latitude=[], longitude=[])
            empty_data = GeoSpatialData(
                empty_df, Dict(), "POINT", "EPSG:4326",
                (minx=0, miny=0, maxx=0, maxy=0), nothing
            )
            animate_timeseries(empty_data, "timestamp", "value")
        end

        # Test error handling: missing timestamp
        @test_throws ErrorException begin
            data = create_test_geospatial_data()
            animate_timeseries(data, "bad_time", "temperature")
        end

        # Test error handling: missing value column
        @test_throws ErrorException begin
            data = create_test_geospatial_data()
            animate_timeseries(data, "timestamp", "nonexistent")
        end
    end

    # ========================================================================
    # GeoJSON Export Tests
    # ========================================================================

    @testset "GeoJSON Export" begin

        @test begin
            data = create_test_geospatial_data()
            result = export_geojson(data, tempname() * ".geojson")
            result == true
        end

        @test begin
            data = create_test_geospatial_data()
            filepath = tempname() * ".geojson"
            export_geojson(data, filepath)
            isfile(filepath)
        end

        @test begin
            data = create_test_geospatial_data()
            filepath = tempname() * ".geojson"
            export_geojson(data, filepath)
            content = read(filepath, String)
            contains(content, "FeatureCollection")
        end

        @test begin
            data = create_test_geospatial_data()
            filepath = tempname() * ".geojson"
            export_geojson(data, filepath)
            content = read(filepath, String)
            contains(content, "Feature")
        end

        @test begin
            data = create_test_geospatial_data()
            filepath = tempname() * ".geojson"
            export_geojson(data, filepath)
            content = read(filepath, String)
            contains(content, "Point")
        end

        # Test error handling: empty data
        @test begin
            empty_df = DataFrame(latitude=[], longitude=[])
            empty_data = GeoSpatialData(
                empty_df, Dict(), "POINT", "EPSG:4326",
                (minx=0, miny=0, maxx=0, maxy=0), nothing
            )
            export_geojson(empty_data, tempname() * ".geojson") == false
        end

        # Test error handling: missing coordinates
        @test_throws ErrorException begin
            bad_df = DataFrame(name=["A", "B"])
            bad_data = GeoSpatialData(
                bad_df, Dict(), "POINT", "EPSG:4326",
                (minx=0, miny=0, maxx=1, maxy=1), nothing
            )
            export_geojson(bad_data, tempname() * ".geojson")
        end
    end

    # ========================================================================
    # GeoTIFF Export Tests
    # ========================================================================

    @testset "GeoTIFF Export" begin

        @test begin
            data = create_test_geospatial_data()
            result = export_geotiff(data, tempname() * ".tiff", "temperature")
            result == true
        end

        @test begin
            data = create_test_geospatial_data()
            result = export_geotiff(data, tempname() * ".tiff", "humidity")
            result == true
        end

        # Test error handling: missing variable
        @test_throws ErrorException begin
            data = create_test_geospatial_data()
            export_geotiff(data, tempname() * ".tiff", "nonexistent")
        end
    end

    # ========================================================================
    # Dashboard Tests
    # ========================================================================

    @testset "Interactive Dashboards" begin

        @test begin
            data = create_test_geospatial_data()
            engine = GeoSpatialAnalysisEngine()
            results = [
                AnalysisResult(
                    "test_result",
                    data,
                    Dict("metric" => 0.95),
                    "test_analysis"
                )
            ]
            html = create_interactive_dashboard(engine, results)
            html isa String
        end

        @test begin
            data = create_test_geospatial_data()
            engine = GeoSpatialAnalysisEngine()
            results = [
                AnalysisResult(
                    "test",
                    data,
                    Dict("metric" => 0.95),
                    "analysis"
                )
            ]
            html = create_interactive_dashboard(engine, results)
            contains(html, "leaflet")
        end

        @test begin
            data = create_test_geospatial_data()
            engine = GeoSpatialAnalysisEngine()
            results = [
                AnalysisResult(
                    "test",
                    data,
                    Dict("metric" => 0.95),
                    "analysis"
                )
            ]
            html = create_interactive_dashboard(engine, results)
            contains(html, "GeoSpatial Analysis Dashboard")
        end
    end

    # ========================================================================
    # Publishing Tests
    # ========================================================================

    @testset "Publishing Results" begin

        @test begin
            data = create_test_geospatial_data()
            map = create_web_map(data)
            result = publish_results(map, "local")
            result isa String && !isempty(result)
        end

        @test begin
            data = create_test_geospatial_data()
            map = create_web_map(data)
            filepath = publish_results(map, "local")
            contains(filepath, ".html")
        end

        @test begin
            data = create_test_geospatial_data()
            map = create_web_map(data)
            # GitHub publishing returns URL (warning logged)
            result = publish_results(map, "github")
            result isa String
        end

        @test begin
            data = create_test_geospatial_data()
            map = create_web_map(data)
            # Unknown service throws error
            try
                publish_results(map, "unknown_service")
                false
            catch e
                contains(string(e), "Unknown publication service")
            end
        end
    end

    # ========================================================================
    # Integration Tests
    # ========================================================================

    @testset "Visualization Workflows" begin

        @test begin
            # Complete workflow: create data → visualize → export
            data = create_test_geospatial_data()

            # Create map
            map = create_web_map(data)
            map_valid = map isa InteractiveMap

            # Create heatmap
            heatmap = render_heatmap(data, "temperature")
            heatmap_valid = heatmap isa InteractiveMap

            # Create 3D visualization
            viz = create_3d_visualization(data, "temperature")
            viz_valid = viz isa Dict

            # Export
            geojson_file = tempname() * ".geojson"
            export_valid = export_geojson(data, geojson_file)

            # All should succeed
            map_valid && heatmap_valid && viz_valid && export_valid
        end

        @test begin
            # Chained operations
            data = create_test_geospatial_data()

            # Create visualizations
            maps = [
                create_web_map(data; title="Temperature Map"),
                create_web_map(data; title="Humidity Map"),
                render_heatmap(data, "temperature"),
                render_heatmap(data, "humidity")
            ]

            all(m -> m isa InteractiveMap, maps)
        end

        @test begin
            # Time-series visualization workflow
            data = create_test_geospatial_data()

            # Create animation
            anim = animate_timeseries(data, "timestamp", "temperature")
            anim_valid = haskey(anim, "frames")

            # Export results
            geojson_file = tempname() * ".geojson"
            export_valid = export_geojson(data, geojson_file)

            anim_valid && export_valid
        end
    end

end

println("\n✅ All visualization tests passed!")
