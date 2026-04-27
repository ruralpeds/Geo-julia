"""
Tests for Census API client with mocked responses.
"""

# Mock Census API responses for testing
const MOCK_CENSUS_RESPONSES = Dict(
    "rooftop_match" => Dict(
        "result" => Dict(
            "addressMatches" => [
                Dict(
                    "matchedAddress" => "123 Main Street, New York, NY 10001",
                    "coordinates" => Dict("x" => -74.0060, "y" => 40.7128),
                    "tigerLineId" => "123456789",
                    "addressType" => "Rooftop",
                    "inputId" => 1
                )
            ]
        )
    ),
    "range_match" => Dict(
        "result" => Dict(
            "addressMatches" => [
                Dict(
                    "matchedAddress" => "123-125 Main Street, New York, NY 10001",
                    "coordinates" => Dict("x" => -74.0061, "y" => 40.7129),
                    "tigerLineId" => "987654321",
                    "addressType" => "Range",
                    "inputId" => 1
                )
            ]
        )
    ),
    "street_match" => Dict(
        "result" => Dict(
            "addressMatches" => [
                Dict(
                    "matchedAddress" => "Main Street, New York, NY 10001",
                    "coordinates" => Dict("x" => -74.0062, "y" => 40.7130),
                    "tigerLineId" => "111222333",
                    "addressType" => "Street",
                    "inputId" => 1
                )
            ]
        )
    ),
    "no_match" => Dict(
        "result" => Dict(
            "addressMatches" => []
        )
    ),
    "error_response" => Dict(
        "errors" => [
            Dict("message" => "Invalid API key")
        ]
    )
)

@testset "parse_census_response" begin
    # Test rooftop match
    response = MOCK_CENSUS_RESPONSES["rooftop_match"]
    result = Geocode.parse_census_response(response, "123 Main St")
    @test result.error === nothing
    @test result.latitude == 40.7128
    @test result.longitude == -74.0060
    @test result.match_quality == Geocode.ROOFTOP
    @test result.source == "census"

    # Test range match
    response = MOCK_CENSUS_RESPONSES["range_match"]
    result = Geocode.parse_census_response(response, "123 Main St")
    @test result.error === nothing
    @test result.match_quality == Geocode.RANGE

    # Test street match
    response = MOCK_CENSUS_RESPONSES["street_match"]
    result = Geocode.parse_census_response(response, "Main St")
    @test result.error === nothing
    @test result.match_quality == Geocode.STREET

    # Test no match
    response = MOCK_CENSUS_RESPONSES["no_match"]
    result = Geocode.parse_census_response(response, "Nonexistent Address")
    @test result.error !== nothing
    @test contains(result.error, "No matches")

    # Test error response
    response = MOCK_CENSUS_RESPONSES["error_response"]
    result = Geocode.parse_census_response(response, "Any Address")
    @test result.error !== nothing
    @test contains(result.error, "Invalid API key")
end

@testset "determine_match_quality" begin
    # Test with addressType field
    match_rooftop = Dict("addressType" => "Rooftop", "matchedAddress" => "123 Main St")
    @test Geocode.determine_match_quality(match_rooftop) == Geocode.ROOFTOP

    match_range = Dict("addressType" => "Range", "matchedAddress" => "123-125 Main St")
    @test Geocode.determine_match_quality(match_range) == Geocode.RANGE

    match_street = Dict("addressType" => "Street", "matchedAddress" => "Main St")
    @test Geocode.determine_match_quality(match_street) == Geocode.STREET

    # Test without explicit type (heuristic)
    match_with_address = Dict("matchedAddress" => "123 Main St")
    quality = Geocode.determine_match_quality(match_with_address)
    @test quality != Geocode.UNKNOWN

    # Test empty match
    match_empty = Dict()
    @test Geocode.determine_match_quality(match_empty) == Geocode.UNKNOWN
end

@testset "extract_error_message" begin
    # Test various HTTP status codes
    response_400 = HTTP.Response(400, "")
    @test contains(Geocode.extract_error_message(response_400), "400")

    response_401 = HTTP.Response(401, "")
    @test contains(Geocode.extract_error_message(response_401), "401")

    response_403 = HTTP.Response(403, "")
    @test contains(Geocode.extract_error_message(response_403), "403")

    response_500 = HTTP.Response(500, "")
    @test contains(Geocode.extract_error_message(response_500), "500")

    response_503 = HTTP.Response(503, "")
    @test contains(Geocode.extract_error_message(response_503), "503")
end

@testset "RateLimiter" begin
    # Create a fast limiter for testing (100 req/sec)
    limiter = Geocode.RateLimiter(100.0)

    # Should be able to acquire tokens quickly
    start = time()
    for i in 1:5
        Geocode.acquire!(limiter)
    end
    elapsed = time() - start

    # Should be very fast (< 100ms for 5 tokens at 100 req/sec)
    @test elapsed < 0.1

    # Create slow limiter (1 req/sec)
    slow_limiter = Geocode.RateLimiter(1.0)

    # First acquire should be instant
    start = time()
    Geocode.acquire!(slow_limiter)
    elapsed = time() - start
    @test elapsed < 0.01

    # Second acquire should wait ~1 second
    start = time()
    Geocode.acquire!(slow_limiter)
    elapsed = time() - start
    @test elapsed >= 0.9  # Allow some tolerance
end

@testset "process_census_batch_response" begin
    # Test with multiple matches
    response = Dict(
        "result" => Dict(
            "addressMatches" => [
                Dict(
                    "matchedAddress" => "123 Main St, City, ST",
                    "coordinates" => Dict("x" => -74.0, "y" => 40.0),
                    "inputId" => 1
                ),
                Dict(
                    "matchedAddress" => "456 Oak Ave, City, ST",
                    "coordinates" => Dict("x" => -118.0, "y" => 34.0),
                    "inputId" => 2
                )
            ]
        )
    )

    addresses = ["123 Main St", "456 Oak Ave"]
    results = Geocode.process_census_batch_response(response, addresses)

    @test length(results) == 2
    @test results[1].latitude == 40.0
    @test results[1].longitude == -74.0
    @test results[2].latitude == 34.0
    @test results[2].longitude == -118.0
end

@testset "validate_api_key" begin
    @test Geocode.validate_api_key("valid_api_key_1234567890") == true
    @test Geocode.validate_api_key("short") == false
    @test Geocode.validate_api_key("") == false
    @test Geocode.validate_api_key("   ") == false
end

@testset "get_api_key resolution order" begin
    # Save original env
    original_env = get(ENV, "CENSUS_API_KEY", nothing)

    try
        # Test 1: Provided key has priority
        provided_key = "provided_key_123456789"
        resolved = Geocode.get_api_key(provided_key)
        @test resolved == provided_key

        # Test 2: Empty provided key falls back to ENV
        ENV["CENSUS_API_KEY"] = "env_key_123456789"
        resolved = Geocode.get_api_key("")
        @test resolved == "env_key_123456789"

        # Test 3: Explicit nothing falls back to ENV
        resolved = Geocode.get_api_key(nothing)
        @test resolved == "env_key_123456789"

    finally
        # Restore original env
        if original_env !== nothing
            ENV["CENSUS_API_KEY"] = original_env
        else
            delete!(ENV, "CENSUS_API_KEY")
        end
    end
end
