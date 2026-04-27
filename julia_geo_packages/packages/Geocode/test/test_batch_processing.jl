"""
Tests for batch geocoding with caching and progress tracking.
"""

@testset "batch_geocode with vector input" begin
    Geocode.clear_cache()

    # Create test addresses
    addresses = [
        "123 Main St, New York",
        "456 Oak Ave, Los Angeles",
        "789 Pine Rd, Chicago"
    ]

    # Cache some results first
    for (i, addr) in enumerate(addresses)
        result = Geocode.GeocodeResult(
            addr,
            40.0 + i,
            -74.0 - i,
            Geocode.STREET,
            "census",
            addr
        )
        Geocode.cache_result(result)
    end

    # Batch geocode (should get from cache)
    results = Geocode.batch_geocode(addresses; show_progress=false)

    @test length(results) == 3
    @test all(r -> r.error === nothing, results)
    @test all(r -> r.source == "cache", results)

    # Verify order is preserved
    @test results[1].address == addresses[1]
    @test results[2].address == addresses[2]
    @test results[3].address == addresses[3]

    # Verify coordinates
    @test results[1].latitude == 41.0
    @test results[2].latitude == 42.0
    @test results[3].latitude == 43.0
end

@testset "batch_geocode with DataFrame input" begin
    Geocode.clear_cache()

    # Create test DataFrame
    df = DataFrame(
        address = [
            "100 Main St",
            "200 Oak Ave",
            "300 Pine Rd"
        ]
    )

    # Cache results
    for (i, addr) in enumerate(df.address)
        result = Geocode.GeocodeResult(
            addr,
            50.0 + i,
            -100.0 - i,
            Geocode.STREET,
            "census"
        )
        Geocode.cache_result(result)
    end

    # Batch geocode
    results = Geocode.batch_geocode(df; show_progress=false)

    @test length(results) == 3
    @test results[1].latitude == 51.0
    @test results[2].latitude == 52.0
end

@testset "batch_geocode_to_dataframe" begin
    Geocode.clear_cache()

    addresses = ["123 Main St", "456 Oak Ave"]

    # Cache results
    for (i, addr) in enumerate(addresses)
        result = Geocode.GeocodeResult(
            addr,
            30.0 + i,
            -85.0 - i,
            Geocode.STREET,
            "cache"
        )
        Geocode.cache_result(result)
    end

    # Convert to DataFrame
    result_df = Geocode.batch_geocode_to_dataframe(addresses; show_progress=false)

    @test nrow(result_df) == 2
    @test result_df[1, :address] == "123 Main St"
    @test result_df[1, :latitude] == 31.0
    @test result_df[1, :source] == "cache"
    @test result_df[1, :error] == nothing

    @test result_df[2, :address] == "456 Oak Ave"
    @test result_df[2, :latitude] == 32.0

    # Verify columns exist
    col_names = names(result_df)
    @test "address" in col_names
    @test "latitude" in col_names
    @test "longitude" in col_names
    @test "match_quality" in col_names
    @test "source" in col_names
    @test "matched_address" in col_names
    @test "error" in col_names
end

@testset "batch_geocode handles duplicates efficiently" begin
    Geocode.clear_cache()

    # Addresses with duplicates
    addresses = [
        "123 Main St",
        "456 Oak Ave",
        "123 Main St",  # Duplicate
        "789 Pine Rd",
        "456 Oak Ave"   # Duplicate
    ]

    # Cache first two unique addresses
    result1 = Geocode.GeocodeResult("123 Main St", 40.0, -74.0, Geocode.STREET, "census")
    result2 = Geocode.GeocodeResult("456 Oak Ave", 34.0, -118.0, Geocode.STREET, "census")
    Geocode.cache_result(result1)
    Geocode.cache_result(result2)

    # Batch geocode - cache should be hit for duplicates
    results = Geocode.batch_geocode(addresses; show_progress=false)

    @test length(results) == 5
    # All results should be in same order as input
    @test results[1].address == "123 Main St"
    @test results[3].address == "123 Main St"
    @test results[2].address == "456 Oak Ave"
    @test results[5].address == "456 Oak Ave"
end

@testset "batch_geocode with retry" begin
    Geocode.clear_cache()

    addresses = ["123 Main St", "456 Oak Ave"]

    # Cache at least one result
    result = Geocode.GeocodeResult("123 Main St", 40.0, -74.0, Geocode.STREET, "census")
    Geocode.cache_result(result)

    # Other address will fail but should be retried
    results = Geocode.batch_geocode(addresses; retry=2, show_progress=false)

    @test length(results) == 2
    @test results[1].error === nothing
end

@testset "batch_geocode empty input" begin
    results = Geocode.batch_geocode(String[]; show_progress=false)
    @test length(results) == 0

    results = Geocode.batch_geocode(DataFrame(address=String[]); show_progress=false)
    @test length(results) == 0
end

@testset "batch_geocode batch_size clamping" begin
    Geocode.clear_cache()

    addresses = ["123 Main St", "456 Oak Ave"]

    # Cache results so they don't actually need geocoding
    for (i, addr) in enumerate(addresses)
        result = Geocode.GeocodeResult(addr, 40.0 + i, -74.0 - i, Geocode.STREET, "census")
        Geocode.cache_result(result)
    end

    # Test batch_size is clamped
    results1 = Geocode.batch_geocode(addresses; batch_size=0, show_progress=false)
    results2 = Geocode.batch_geocode(addresses; batch_size=200, show_progress=false)

    @test length(results1) == 2
    @test length(results2) == 2
end

@testset "geocode single address" begin
    Geocode.clear_cache()

    address = "123 Test St"
    result = Geocode.GeocodeResult(address, 40.0, -74.0, Geocode.STREET, "census")
    Geocode.cache_result(result)

    # Single geocode should hit cache
    geocoded = Geocode.geocode(address)
    @test geocoded.source == "cache"
    @test geocoded.latitude == 40.0
    @test geocoded.longitude == -74.0
end

@testset "batch_geocode preserves order" begin
    Geocode.clear_cache()

    addresses = ["Addr A", "Addr B", "Addr C", "Addr D", "Addr E"]

    # Cache in specific order with specific coordinates
    for (i, addr) in enumerate(addresses)
        result = Geocode.GeocodeResult(
            addr,
            Float64(i * 10),
            Float64(i * -10),
            Geocode.STREET,
            "census"
        )
        Geocode.cache_result(result)
    end

    results = Geocode.batch_geocode(addresses; show_progress=false)

    # Verify order is preserved
    for (i, result) in enumerate(results)
        @test result.address == addresses[i]
        @test result.latitude == i * 10.0
    end
end
