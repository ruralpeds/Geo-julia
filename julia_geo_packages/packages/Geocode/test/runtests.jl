using Geocode
using Test
using DataFrames
using JSON

@testset "Geocode.jl Tests" begin
    # Test 1: Types and basic structure
    @test Geocode.ROOFTOP == Geocode.QualityLevel(4)
    @test Geocode.CITY == Geocode.QualityLevel(1)

    # Test 2: GeocodeResult construction
    result = Geocode.GeocodeResult(
        "123 Main St",
        40.7128,
        -74.0060,
        Geocode.ROOFTOP,
        "census",
        "123 Main Street, New York, NY"
    )
    @test result.address == "123 Main St"
    @test result.latitude == 40.7128
    @test result.longitude == -74.0060
    @test result.match_quality == Geocode.ROOFTOP
    @test result.source == "census"
    @test result.error === nothing

    # Test 3: Error result construction
    error_result = Geocode.GeocodeResult("Invalid Address", "Not found")
    @test error_result.address == "Invalid Address"
    @test error_result.error == "Not found"
    @test error_result.match_quality == Geocode.UNKNOWN
    @test isnan(error_result.latitude)
    @test isnan(error_result.longitude)

    # Test 4: Address standardization
    @test Geocode.standardize_address("123  Main  ST., NEW YORK, NY") == "123 main st new york ny"
    @test Geocode.standardize_address("456 Oak Ave") == "456 oak ave"
    @test Geocode.standardize_address("  100  Elm  Rd  ") == "100 elm rd"

    # Test 5: Address hashing
    hash1 = Geocode.address_hash("123 Main St")
    hash2 = Geocode.address_hash("123 Main St")
    @test hash1 == hash2  # Deterministic

    # Different addresses should have different hashes
    hash3 = Geocode.address_hash("456 Oak Ave")
    @test hash1 != hash3

    # Standardization should be used in hashing
    hash4 = Geocode.address_hash("123  MAIN  ST")
    @test hash1 == hash4  # Should match after standardization

    # Test 6: Coordinate validation
    @test Geocode.is_valid_coordinate(0, 0) == true
    @test Geocode.is_valid_coordinate(40.7128, -74.0060) == true
    @test Geocode.is_valid_coordinate(91, 0) == false
    @test Geocode.is_valid_coordinate(0, 181) == false
    @test Geocode.is_valid_coordinate(NaN, 0) == false

    # Test 7: Quality indicator parsing
    @test Geocode.parse_quality_indicator("Rooftop") == Geocode.ROOFTOP
    @test Geocode.parse_quality_indicator("range") == Geocode.RANGE
    @test Geocode.parse_quality_indicator("Street") == Geocode.STREET
    @test Geocode.parse_quality_indicator("City") == Geocode.CITY
    @test Geocode.parse_quality_indicator("Unknown") == Geocode.UNKNOWN

    # Test 8: Cache initialization
    Geocode.clear_cache()
    db = Geocode.initialize_cache()
    @test db !== nothing

    # Test 9: Cache result storage and retrieval
    address = "123 Test St"
    test_result = Geocode.GeocodeResult(
        address,
        40.0,
        -74.0,
        Geocode.STREET,
        "census",
        "123 Test Street"
    )
    Geocode.cache_result(test_result)

    # Retrieve from cache
    cached = Geocode.get_cached_result(address)
    @test cached !== nothing
    @test cached.address == address
    @test cached.latitude == 40.0
    @test cached.longitude == -74.0
    @test cached.source == "cache"

    # Test 10: Error results don't get cached
    error_res = Geocode.GeocodeResult("Bad Addr", "Not found")
    Geocode.cache_result(error_res)
    cached_err = Geocode.get_cached_result("Bad Addr")
    @test cached_err === nothing

    # Test 11: Cache statistics
    Geocode.clear_cache()
    stats = Geocode.get_cache_stats()
    @test stats.total == 0

    # Add a result and check stats
    Geocode.cache_result(test_result)
    stats = Geocode.get_cache_stats()
    @test stats.total >= 1
    @test stats.active >= 1

    # Test 12: Rate limiter
    limiter = Geocode.RateLimiter(100.0)  # Fast limiter for testing
    start = Base.Libc.time()
    for i in 1:5
        Geocode.acquire!(limiter)
    end
    elapsed = Base.Libc.time() - start
    @test elapsed < 0.5  # Should be very fast

    # Test 13: Nominatim quality determination
    @test Geocode.determine_nominatim_quality("house", "building") == Geocode.STREET
    @test Geocode.determine_nominatim_quality("street", "highway") == Geocode.STREET
    @test Geocode.determine_nominatim_quality("city", "place") == Geocode.CITY
    @test Geocode.determine_nominatim_quality("village", "place") == Geocode.CITY

    # Test 14: Fallback decision logic
    good_result = Geocode.GeocodeResult("123 Main", 40.0, -74.0, Geocode.ROOFTOP, "census")
    @test Geocode.should_fallback_to_nominatim(good_result) == false

    unknown_result = Geocode.GeocodeResult("Mystery", NaN, NaN, Geocode.UNKNOWN, "census")
    @test Geocode.should_fallback_to_nominatim(unknown_result) == true

    error_fallback = Geocode.GeocodeResult("Bad", "Not found")
    @test Geocode.should_fallback_to_nominatim(error_fallback) == true

    # Test 15: Result comparison
    census_high = Geocode.GeocodeResult("Test", 40.0, -74.0, Geocode.ROOFTOP, "census")
    nominatim_low = Geocode.GeocodeResult("Test", 40.0, -74.0, Geocode.CITY, "nominatim")
    best = Geocode.compare_results(census_high, nominatim_low)
    @test best.source == "census"

    # Test 16: Batch geocode with DataFrame
    Geocode.clear_cache()
    addresses = ["Addr A", "Addr B", "Addr C"]

    # Pre-cache some results
    for (i, addr) in enumerate(addresses)
        res = Geocode.GeocodeResult(addr, Float64(40 + i), Float64(-74 - i), Geocode.STREET, "census")
        Geocode.cache_result(res)
    end

    # Batch geocode should retrieve from cache
    results = Geocode.batch_geocode(addresses; show_progress=false)
    @test length(results) == 3
    @test all(r -> r.error === nothing, results)
    @test all(r -> r.source == "cache", results)
    @test results[1].latitude == 41.0
    @test results[2].latitude == 42.0

    # Test 17: DataFrame round-trip
    result_df = Geocode.batch_geocode_to_dataframe(addresses; show_progress=false)
    @test nrow(result_df) == 3
    @test result_df[1, :address] == "Addr A"
    @test result_df[1, :source] == "cache"

    # Test 18: Single geocode function
    Geocode.clear_cache()
    test_addr = "100 Test Ave"
    res = Geocode.GeocodeResult(test_addr, 35.0, -85.0, Geocode.STREET, "census")
    Geocode.cache_result(res)

    geocoded = Geocode.geocode(test_addr)
    @test geocoded.address == test_addr
    @test geocoded.source == "cache"
    @test geocoded.latitude == 35.0

    # Test 19: API key validation
    @test Geocode.validate_api_key("valid_key_1234567890") == true
    @test Geocode.validate_api_key("short") == false
    @test Geocode.validate_api_key("") == false

    # Test 20: CensusMatch type
    match = Geocode.CensusMatch("Rooftop", "123456789", "L")
    @test match.match_indicator == "Rooftop"
    @test match.tigerline_id == "123456789"
    @test match.side == "L"

    println("\nAll tests passed successfully!")
end
