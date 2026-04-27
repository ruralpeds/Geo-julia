"""
Integration tests for full geocoding workflow.
"""

@testset "Full workflow: cache hit" begin
    Geocode.clear_cache()

    address = "100 Main St, Springfield"

    # First call: not in cache
    # We'll manually put it in cache to simulate a previous call
    result1 = Geocode.GeocodeResult(
        address,
        39.7817,
        -89.6501,
        Geocode.ROOFTOP,
        "census",
        "100 Main Street, Springfield, IL"
    )
    Geocode.cache_result(result1)

    # Second call: should hit cache
    result2 = Geocode.geocode(address)

    @test result2.source == "cache"
    @test result2.latitude == 39.7817
    @test result2.longitude == -89.6501
    @test result2.match_quality == Geocode.ROOFTOP
end

@testset "Full workflow: batch with mixed sources" begin
    Geocode.clear_cache()

    addresses = [
        "123 Main St, NYC",
        "456 Oak Ave, LA",
        "789 Pine Rd, Chicago"
    ]

    # Cache first address
    cached_result = Geocode.GeocodeResult(
        addresses[1],
        40.7128,
        -74.0060,
        Geocode.ROOFTOP,
        "census"
    )
    Geocode.cache_result(cached_result)

    # Batch geocode
    results = Geocode.batch_geocode(addresses; show_progress=false)

    # First should be from cache
    @test results[1].source == "cache"
    @test results[1].match_quality == Geocode.ROOFTOP

    # All should have valid structure
    @test length(results) == 3
    for result in results
        @test !isempty(result.address)
    end
end

@testset "Full workflow: standardization consistency" begin
    Geocode.clear_cache()

    # Different formats of same address
    address_variations = [
        "123 Main St., New York, NY",
        "123  MAIN  ST., NEW YORK, NY",
        "123 main st, new york, ny"
    ]

    # Cache result for first variation
    result = Geocode.GeocodeResult(
        address_variations[1],
        40.7128,
        -74.0060,
        Geocode.STREET,
        "census"
    )
    Geocode.cache_result(result)

    # All variations should hit the same cache
    cached1 = Geocode.get_cached_result(address_variations[1])
    cached2 = Geocode.get_cached_result(address_variations[2])
    cached3 = Geocode.get_cached_result(address_variations[3])

    @test cached1 !== nothing
    @test cached2 !== nothing
    @test cached3 !== nothing

    # All should refer to the original cached address
    @test cached1.address == address_variations[1]
    @test cached2.address == address_variations[1]
    @test cached3.address == address_variations[1]
end

@testset "Full workflow: quality level progression" begin
    Geocode.clear_cache()

    test_cases = [
        ("123 Main St", Geocode.ROOFTOP, "Exact match"),
        ("123-125 Main St", Geocode.RANGE, "Address range"),
        ("Main St", Geocode.STREET, "Street level"),
        ("New York", Geocode.CITY, "City level")
    ]

    # Create and cache results with different quality levels
    for (addr, quality, desc) in test_cases
        result = Geocode.GeocodeResult(
            addr,
            40.0,
            -74.0,
            quality,
            "test",
            addr
        )
        Geocode.cache_result(result)
    end

    # Retrieve and verify quality levels
    for (addr, expected_quality, desc) in test_cases
        result = Geocode.get_cached_result(addr)
        @test result !== nothing
        @test result.match_quality == expected_quality
    end
end

@testset "Full workflow: error handling and recovery" begin
    Geocode.clear_cache()

    # Test that error results don't get cached
    error_result = Geocode.GeocodeResult("Bad Address", "Not found")
    @test error_result.error !== nothing

    Geocode.cache_result(error_result)  # Try to cache error

    # Should not be in cache
    cached = Geocode.get_cached_result("Bad Address")
    @test cached === nothing
end

@testset "Full workflow: data frame round trip" begin
    Geocode.clear_cache()

    # Create sample data
    input_df = DataFrame(
        address = [
            "123 Main St",
            "456 Oak Ave",
            "789 Pine Rd"
        ]
    )

    # Cache results
    for (i, addr) in enumerate(input_df.address)
        result = Geocode.GeocodeResult(
            addr,
            Float64(40 + i),
            Float64(-74 - i),
            Geocode.STREET,
            "census"
        )
        Geocode.cache_result(result)
    end

    # Batch geocode to DataFrame
    output_df = Geocode.batch_geocode_to_dataframe(input_df; show_progress=false)

    # Verify round trip
    @test nrow(output_df) == nrow(input_df)
    @test output_df[1, :latitude] == 41.0
    @test output_df[2, :latitude] == 42.0
    @test output_df[3, :latitude] == 43.0

    # Verify all results are from cache
    @test all(s -> s == "cache", output_df.source)
end

@testset "Full workflow: cache stats" begin
    Geocode.clear_cache()

    # Empty cache
    stats = Geocode.get_cache_stats()
    @test stats.total == 0
    @test stats.active == 0

    # Add results
    addresses = ["Addr1", "Addr2", "Addr3"]
    for addr in addresses
        result = Geocode.GeocodeResult(addr, 40.0, -74.0, Geocode.STREET, "test")
        Geocode.cache_result(result)
    end

    # Check stats
    stats = Geocode.get_cache_stats()
    @test stats.total == 3
    @test stats.active == 3
    @test stats.expired == 0
end

@testset "Full workflow: large batch processing" begin
    Geocode.clear_cache()

    # Generate 100+ addresses
    num_addresses = 150
    addresses = ["Address $i" for i in 1:num_addresses]

    # Cache all of them
    for (i, addr) in enumerate(addresses)
        result = Geocode.GeocodeResult(
            addr,
            Float64(40 + (i % 90)),
            Float64(-74 - (i % 180)),
            Geocode.STREET,
            "census"
        )
        Geocode.cache_result(result)
    end

    # Batch geocode without progress bar for test speed
    results = Geocode.batch_geocode(addresses; show_progress=false)

    @test length(results) == num_addresses
    @test all(r -> r.error === nothing, results)
    @test all(r -> r.source == "cache", results)

    # Verify order preservation with large batch
    for i in 1:10:num_addresses
        @test results[i].address == addresses[i]
    end
end

@testset "Full workflow: quality comparison logic" begin
    # Test that compare_results works in realistic scenario
    census_result = Geocode.GeocodeResult(
        "123 Main St",
        40.7128,
        -74.0060,
        Geocode.ROOFTOP,
        "census"
    )

    nominatim_result = Geocode.GeocodeResult(
        "123 Main St",
        40.7129,
        -74.0061,
        Geocode.CITY,
        "nominatim"
    )

    # Higher quality Census result should be chosen
    best = Geocode.compare_results(census_result, nominatim_result)
    @test best.source == "census"
    @test best.match_quality == Geocode.ROOFTOP
end
