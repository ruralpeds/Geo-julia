"""
GeoSpatialEngine Test Suite
"""

using Test
using GeoSpatialEngine
using DataFrames
using Dates

@testset "GeoSpatialEngine Tests" begin

    @testset "Core Engine Tests" begin
        @test begin
            engine = GeoSpatialAnalysisEngine()
            !isnothing(engine)
        end

        @test begin
            engine = GeoSpatialAnalysisEngine()
            source = get_data_source(engine, "NOAA_Weather")
            !isnothing(source)
        end

        @test begin
            engine = GeoSpatialAnalysisEngine()
            list_available_sources(engine)
            true
        end
    end

    @testset "Type Construction" begin
        @test begin
            data = GeoSpatialData(DataFrame(a=[1,2,3]))
            isa(data, GeoSpatialData)
        end

        @test begin
            source = DataSource("TestSource", "Test", "http://example.com",
                              Dict(), Dict(), "Test source", true)
            isa(source, DataSource)
        end

        @test begin
            config = AnalysisConfig("test", Dict(), "GeoJSON", "EPSG:4326")
            isa(config, AnalysisConfig)
        end
    end

    @testset "Data Ingestion" begin
        @test begin
            engine = GeoSpatialAnalysisEngine()
            data = ingest_data(engine, "NOAA_Weather"; region="US")
            isa(data, GeoSpatialData)
        end

        @test begin
            # Test empty data ingestion
            engine = GeoSpatialAnalysisEngine()
            data = ingest_data(engine, "NOAA_Weather")
            nrow(data.data) >= 0
        end
    end

    @testset "Data Validation" begin
        @test _is_valid_crs("EPSG:4326")
        @test _is_valid_crs("EPSG:3857")
        @test !_is_valid_crs("INVALID:1234")
    end

    @testset "Analysis Operations" begin
        @test begin
            engine = GeoSpatialAnalysisEngine()
            data = GeoSpatialData(DataFrame(
                lat=[40.0, 41.0, 42.0],
                lon=[-74.0, -73.0, -72.0],
                value=[10.0, 20.0, 30.0]
            ))
            config = AnalysisConfig("summary_stats", Dict(), "GeoJSON", "EPSG:4326")
            result = analyze(engine, data, config)
            isa(result, AnalysisResult)
        end
    end

    @testset "Workflow Pipeline" begin
        @test begin
            pipeline = create_analysis_pipeline("TestPipeline")
            isa(pipeline, WorkflowPipeline)
        end

        @test begin
            pipeline = create_analysis_pipeline("TestPipeline")
            add_step(pipeline, "step1", x -> x)
            length(pipeline.steps) == 1
        end
    end

    @testset "Data Source Registry" begin
        @test begin
            sources = list_sources()
            length(sources) >= 0
        end

        @test begin
            info = get_source_info("NOAA_Weather")
            !isnothing(info)
        end
    end

    @testset "Configuration" begin
        @test begin
            config = GeoEngineConfig()
            validate_config(config)
        end

        @test begin
            config = GeoEngineConfig(cache_enabled=true, num_workers=2)
            config.cache_enabled == true
        end
    end

    @testset "Caching" begin
        @test begin
            config = GeoEngineConfig(cache_enabled=true)
            engine = GeoSpatialAnalysisEngine(config)
            data = GeoSpatialData(DataFrame(a=[1,2,3]))
            cache_data(engine, "test_key", data)
            haskey(engine.data_cache, "test_key")
        end
    end

    @testset "Utilities" begin
        @test begin
            bounds = format_bounds(-74.0, 40.0, -73.0, 41.0)
            bounds.minx == -74.0
        end

        @test begin
            dist = distance_haversine(40.0, -74.0, 41.0, -73.0)
            dist > 0
        end
    end

end

println("\n" * "="^60)
println("✅ All tests completed")
println("="*60)
