"""
Tests for utility functions.
"""

@testset "standardize_address" begin
    # Test whitespace normalization
    @test Geocode.standardize_address("123  Main  St") == "123 main st"

    # Test case conversion
    @test Geocode.standardize_address("123 MAIN ST") == "123 main st"

    # Test punctuation removal
    @test Geocode.standardize_address("123 Main St., New York, NY") == "123 main st new york ny"
    @test Geocode.standardize_address("123-A Main St") == "123a main st"

    # Test leading/trailing whitespace
    @test Geocode.standardize_address("  123 Main St  ") == "123 main st"

    # Test complex address
    standardized = Geocode.standardize_address("123 Main St., New York, NY 10001")
    @test standardized == "123 main st new york ny 10001"
end

@testset "address_hash" begin
    # Test deterministic hash
    hash1 = Geocode.address_hash("123 Main St")
    hash2 = Geocode.address_hash("123 Main St")
    @test hash1 == hash2

    # Test that different addresses have different hashes
    hash3 = Geocode.address_hash("456 Oak Ave")
    @test hash1 != hash3

    # Test that standardization is used
    hash4 = Geocode.address_hash("123  MAIN  ST")
    @test hash1 == hash4  # Should match after standardization

    # Test hash format
    @test length(hash1) == 64  # SHA256 hex is 64 chars
    @test all(c -> c in "0123456789abcdef", hash1)
end

@testset "deduplicate_addresses" begin
    addresses = ["123 Main St", "456 Oak Ave", "123 Main St", "789 Pine Rd", "456 Oak Ave", "456 Oak Ave"]

    dedup = Geocode.deduplicate_addresses(addresses)

    # Should have 3 unique addresses after standardization
    @test length(dedup) == 3

    # Check that standardized addresses are used as keys
    @test any(startswith(k, "123") for k in keys(dedup))
    @test any(startswith(k, "456") for k in keys(dedup))
    @test any(startswith(k, "789") for k in keys(dedup))
end

@testset "parse_quality_indicator" begin
    @test Geocode.parse_quality_indicator("Rooftop") == Geocode.ROOFTOP
    @test Geocode.parse_quality_indicator("rooftop") == Geocode.ROOFTOP
    @test Geocode.parse_quality_indicator("ROOFTOP") == Geocode.ROOFTOP

    @test Geocode.parse_quality_indicator("Range") == Geocode.RANGE
    @test Geocode.parse_quality_indicator("range") == Geocode.RANGE

    @test Geocode.parse_quality_indicator("Street") == Geocode.STREET
    @test Geocode.parse_quality_indicator("street") == Geocode.STREET

    @test Geocode.parse_quality_indicator("City") == Geocode.CITY
    @test Geocode.parse_quality_indicator("city") == Geocode.CITY

    @test Geocode.parse_quality_indicator("Unknown") == Geocode.UNKNOWN
    @test Geocode.parse_quality_indicator("xyz") == Geocode.UNKNOWN
end

@testset "is_valid_coordinate" begin
    # Valid coordinates
    @test Geocode.is_valid_coordinate(0, 0) == true
    @test Geocode.is_valid_coordinate(40.7128, -74.0060) == true
    @test Geocode.is_valid_coordinate(-90, -180) == true
    @test Geocode.is_valid_coordinate(90, 180) == true

    # Invalid coordinates
    @test Geocode.is_valid_coordinate(91, 0) == false
    @test Geocode.is_valid_coordinate(-91, 0) == false
    @test Geocode.is_valid_coordinate(0, 181) == false
    @test Geocode.is_valid_coordinate(0, -181) == false

    # NaN/Inf
    @test Geocode.is_valid_coordinate(NaN, 0) == false
    @test Geocode.is_valid_coordinate(0, NaN) == false
    @test Geocode.is_valid_coordinate(Inf, 0) == false
    @test Geocode.is_valid_coordinate(0, Inf) == false
end

@testset "parse_address_parts" begin
    # Simple format
    parts = Geocode.parse_address_parts("123 Main St, New York, NY 10001")
    @test contains(parts.street, "123 Main St")
    @test contains(parts.city, "New York")
    @test contains(parts.state, "NY")
    @test contains(parts.zip, "10001")

    # Minimal format
    parts2 = Geocode.parse_address_parts("123 Main St")
    @test contains(parts2.street, "123 Main St")
    @test parts2.city == ""

    # Two parts
    parts3 = Geocode.parse_address_parts("123 Main St, New York")
    @test contains(parts3.street, "123 Main St")
    @test contains(parts3.city, "New York")
end

@testset "format_census_query" begin
    query = Geocode.format_census_query("123 Main St"; city="New York", state="NY", zip="10001")
    @test contains(query, "123 Main St")
    @test contains(query, "New York")
    @test contains(query, "NY")
    @test contains(query, "10001")

    # Partial query
    query2 = Geocode.format_census_query("123 Main St"; city="New York")
    @test contains(query2, "123 Main St")
    @test contains(query2, "New York")
    @test !contains(query2, "state=")
end
