"""
Tests for Nominatim fallback logic.
"""

# Mock Nominatim API responses
const MOCK_NOMINATIM_RESPONSES = Dict(
    "street_match" => [
        Dict(
            "place_id" => 12345,
            "lat" => "40.7128",
            "lon" => "-74.0060",
            "class" => "place",
            "type" => "street",
            "display_name" => "Main Street, New York, NY, USA"
        )
    ],
    "city_match" => [
        Dict(
            "place_id" => 67890,
            "lat" => "40.7306",
            "lon" => "-73.9352",
            "class" => "place",
            "type" => "city",
            "display_name" => "New York, NY, USA"
        )
    ],
    "house_match" => [
        Dict(
            "place_id" => 11111,
            "lat" => "40.7130",
            "lon" => "-74.0062",
            "class" => "building",
            "type" => "house",
            "display_name" => "123 Main Street, New York, NY, USA"
        )
    ],
    "no_match" => []
)

@testset "parse_nominatim_response" begin
    # Test street match
    response = MOCK_NOMINATIM_RESPONSES["street_match"]
    result = Geocode.parse_nominatim_response(response, "Main St")
    @test result.error === nothing
    @test result.latitude == 40.7128
    @test result.longitude == -74.0060
    @test result.match_quality == Geocode.STREET
    @test result.source == "nominatim"

    # Test city match
    response = MOCK_NOMINATIM_RESPONSES["city_match"]
    result = Geocode.parse_nominatim_response(response, "New York")
    @test result.error === nothing
    @test result.match_quality == Geocode.CITY

    # Test house match
    response = MOCK_NOMINATIM_RESPONSES["house_match"]
    result = Geocode.parse_nominatim_response(response, "123 Main St")
    @test result.error === nothing
    @test result.match_quality == Geocode.STREET

    # Test no match
    response = MOCK_NOMINATIM_RESPONSES["no_match"]
    result = Geocode.parse_nominatim_response(response, "Nonexistent")
    @test result.error !== nothing
    @test contains(result.error, "No matches")
end

@testset "determine_nominatim_quality" begin
    # High quality types
    @test Geocode.determine_nominatim_quality("house", "building") == Geocode.STREET
    @test Geocode.determine_nominatim_quality("street", "highway") == Geocode.STREET
    @test Geocode.determine_nominatim_quality("building", "place") == Geocode.STREET

    # City level
    @test Geocode.determine_nominatim_quality("city", "place") == Geocode.CITY
    @test Geocode.determine_nominatim_quality("village", "place") == Geocode.CITY
    @test Geocode.determine_nominatim_quality("town", "place") == Geocode.CITY
    @test Geocode.determine_nominatim_quality("municipality", "place") == Geocode.CITY

    # Boundary (default to city)
    @test Geocode.determine_nominatim_quality("boundary", "boundary") == Geocode.CITY

    # Case insensitivity
    @test Geocode.determine_nominatim_quality("HOUSE", "BUILDING") == Geocode.STREET
    @test Geocode.determine_nominatim_quality("City", "Place") == Geocode.CITY
end

@testset "should_fallback_to_nominatim" begin
    # Error result should trigger fallback
    error_result = Geocode.GeocodeResult("Bad Addr", "Not found")
    @test Geocode.should_fallback_to_nominatim(error_result) == true

    # Unknown quality should trigger fallback
    unknown_result = Geocode.GeocodeResult("Mystery", NaN, NaN, Geocode.UNKNOWN, "census")
    @test Geocode.should_fallback_to_nominatim(unknown_result) == true

    # Successful result should not fallback
    good_result = Geocode.GeocodeResult("123 Main St", 40.0, -74.0, Geocode.ROOFTOP, "census")
    @test Geocode.should_fallback_to_nominatim(good_result) == false

    # Rate limit error should not fallback (avoid hitting Nominatim when Census is throttling)
    rate_limit_error = Geocode.GeocodeResult("Any Addr", "rate limit exceeded")
    @test Geocode.should_fallback_to_nominatim(rate_limit_error) == false
end

@testset "compare_results" begin
    census_rooftop = Geocode.GeocodeResult(
        "123 Main St", 40.7128, -74.0060, Geocode.ROOFTOP, "census", "123 Main St"
    )

    nominatim_city = Geocode.GeocodeResult(
        "New York", 40.7306, -73.9352, Geocode.CITY, "nominatim", "New York, NY"
    )

    # Higher quality (Census rooftop) should win
    result = Geocode.compare_results(census_rooftop, nominatim_city)
    @test result.source == "census"

    # Equal quality should prefer Census
    census_street = Geocode.GeocodeResult(
        "Main St", 40.7, -74.0, Geocode.STREET, "census", "Main St"
    )
    nominatim_street = Geocode.GeocodeResult(
        "Main St", 40.7, -74.0, Geocode.STREET, "nominatim", "Main St"
    )
    result = Geocode.compare_results(census_street, nominatim_street)
    @test result.source == "census"

    # Lower quality Census vs higher quality Nominatim
    census_city = Geocode.GeocodeResult(
        "New York", 40.7, -74.0, Geocode.CITY, "census", "New York"
    )
    nominatim_street = Geocode.GeocodeResult(
        "Main St", 40.7, -74.0, Geocode.STREET, "nominatim", "Main St"
    )
    result = Geocode.compare_results(census_city, nominatim_street)
    @test result.source == "nominatim"

    # Error results
    census_error = Geocode.GeocodeResult("Bad", "Census failed")
    nominatim_ok = Geocode.GeocodeResult(
        "Good", 40.0, -74.0, Geocode.STREET, "nominatim"
    )
    result = Geocode.compare_results(census_error, nominatim_ok)
    @test result.source == "nominatim"

    # Both errors - prefer Census
    nominatim_error = Geocode.GeocodeResult("Bad", "Nominatim failed")
    result = Geocode.compare_results(census_error, nominatim_error)
    @test result.source == "census"
end

@testset "can_use_nominatim" begin
    # This would require network access, so we'll do basic structure test
    # In real integration tests, this would verify connectivity
    @test isa(Geocode.can_use_nominatim(), Bool)
end
