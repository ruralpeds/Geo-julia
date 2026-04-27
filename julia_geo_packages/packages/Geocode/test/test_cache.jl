"""
Tests for caching layer.
"""

@testset "initialize_cache" begin
    # Clear any existing test cache
    Geocode.clear_cache()

    # Initialize cache
    db = Geocode.initialize_cache()
    @test db !== nothing
    @test isa(db, SQLite.DB)

    # Call again should return same connection
    db2 = Geocode.initialize_cache()
    @test db2 === db
end

@testset "cache_result and get_cached_result" begin
    Geocode.clear_cache()

    # Create and cache a result
    address = "123 Main St, Test City"
    result = Geocode.GeocodeResult(
        address,
        40.7128,
        -74.0060,
        Geocode.ROOFTOP,
        "census",
        "123 Main Street, Test City, ST"
    )

    Geocode.cache_result(result)

    # Retrieve from cache
    cached = Geocode.get_cached_result(address)
    @test cached !== nothing
    @test cached.address == address
    @test cached.latitude == 40.7128
    @test cached.longitude == -74.0060
    @test cached.match_quality == Geocode.ROOFTOP
    @test cached.source == "cache"

    # Cache hit for standardized version of address
    cached2 = Geocode.get_cached_result("123  MAIN  ST,  TEST  CITY")
    @test cached2 !== nothing
    @test cached2.address == address
end

@testset "cache ignores error results" begin
    Geocode.clear_cache()

    # Try to cache error result
    error_result = Geocode.GeocodeResult("Bad Address", "Not found")
    Geocode.cache_result(error_result)

    # Should not be in cache
    cached = Geocode.get_cached_result("Bad Address")
    @test cached === nothing
end

@testset "cache ignores unknown quality results" begin
    Geocode.clear_cache()

    # Create result with UNKNOWN quality
    result = Geocode.GeocodeResult("Mystery Address", NaN, NaN, Geocode.UNKNOWN, "test")
    Geocode.cache_result(result)

    # Should not be in cache
    cached = Geocode.get_cached_result("Mystery Address")
    @test cached === nothing
end

@testset "multiple cached results" begin
    Geocode.clear_cache()

    # Cache multiple addresses
    addresses = [
        ("123 Main St", 40.7128, -74.0060),
        ("456 Oak Ave", 34.0522, -118.2437),
        ("789 Pine Rd", 41.8781, -87.6298)
    ]

    for (addr, lat, lon) in addresses
        result = Geocode.GeocodeResult(addr, lat, lon, Geocode.STREET, "census", addr)
        Geocode.cache_result(result)
    end

    # Verify all are cached
    for (addr, lat, lon) in addresses
        cached = Geocode.get_cached_result(addr)
        @test cached !== nothing
        @test cached.latitude == lat
        @test cached.longitude == lon
    end
end

@testset "get_cache_stats" begin
    Geocode.clear_cache()

    # Empty cache
    stats = Geocode.get_cache_stats()
    @test stats.total == 0
    @test stats.active == 0
    @test stats.expired == 0

    # Add one result
    result = Geocode.GeocodeResult("123 Test St", 40.0, -74.0, Geocode.STREET, "census")
    Geocode.cache_result(result)

    stats = Geocode.get_cache_stats()
    @test stats.total == 1
    @test stats.active == 1
    @test stats.expired == 0
end

@testset "clear_cache" begin
    Geocode.clear_cache()

    # Add result
    result = Geocode.GeocodeResult("123 Test St", 40.0, -74.0, Geocode.STREET, "census")
    Geocode.cache_result(result)

    # Verify it's cached
    cached = Geocode.get_cached_result("123 Test St")
    @test cached !== nothing

    # Clear cache
    Geocode.clear_cache()

    # Should not be there anymore
    cached = Geocode.get_cached_result("123 Test St")
    @test cached === nothing
end

@testset "cache_ttl" begin
    Geocode.clear_cache()

    # Create a result and cache it
    result = Geocode.GeocodeResult("TTL Test St", 40.0, -74.0, Geocode.STREET, "census")
    Geocode.cache_result(result)

    # Should be retrievable
    cached = Geocode.get_cached_result("TTL Test St")
    @test cached !== nothing

    # Cleanup should not affect new entries
    Geocode.cleanup_expired_cache()
    cached = Geocode.get_cached_result("TTL Test St")
    @test cached !== nothing
end
