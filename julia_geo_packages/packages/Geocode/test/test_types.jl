"""
Tests for types and data structures.
"""

@testset "GeocodeResult" begin
    # Test successful result construction
    result = GeocodeResult(
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

    # Test error result construction
    error_result = GeocodeResult("Invalid Address", "Not found")
    @test error_result.address == "Invalid Address"
    @test error_result.error == "Not found"
    @test error_result.match_quality == Geocode.UNKNOWN
    @test isnan(error_result.latitude)
    @test isnan(error_result.longitude)

    # Test convenience constructor
    result2 = GeocodeResult("456 Oak Ave", 34.0522, -118.2437, Geocode.STREET, "nominatim")
    @test result2.latitude == 34.0522
    @test result2.longitude == -118.2437
    @test result2.match_quality == Geocode.STREET

    # Test timestamp is set
    @test !isnothing(result.timestamp)
    @test result.timestamp <= now(UTC)
end

@testset "CensusMatch" begin
    match = Geocode.CensusMatch("Rooftop", "123456789", "L")

    @test match.match_indicator == "Rooftop"
    @test match.tigerline_id == "123456789"
    @test match.side == "L"

    # Test optional side
    match2 = Geocode.CensusMatch("Street", "987654321", nothing)
    @test match2.side === nothing
end

@testset "QualityLevel enum" begin
    @test Geocode.ROOFTOP == Geocode.QualityLevel(4)
    @test Geocode.RANGE == Geocode.QualityLevel(3)
    @test Geocode.STREET == Geocode.QualityLevel(2)
    @test Geocode.CITY == Geocode.QualityLevel(1)
    @test Geocode.UNKNOWN == Geocode.QualityLevel(0)

    # Test ordering
    @test Int(Geocode.ROOFTOP) > Int(Geocode.CITY)
    @test Int(Geocode.CITY) > Int(Geocode.UNKNOWN)
end

@testset "show(GeocodeResult)" begin
    result = GeocodeResult(
        "123 Main St",
        40.7128,
        -74.0060,
        Geocode.ROOFTOP,
        "census"
    )

    str = string(result)
    @test contains(str, "123 Main St")
    @test contains(str, "40.7128")
    @test contains(str, "-74.0060")
    @test contains(str, "ROOFTOP")
    @test contains(str, "census")
end
