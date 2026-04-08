using Test
using Geocode

@testset "normalize_address" begin
    @test normalize_address("123 Main St.") == "123 Main Street"
    @test normalize_address("456 Oak Ave") == "456 Oak Avenue"
    @test normalize_address("789 Pine Blvd.") == "789 Pine Boulevard"
    @test normalize_address("  100  Elm  Rd  ") == "100 Elm Road"
    @test normalize_address("Apt. 5A, 200 Maple Dr") == "Apt 5A, 200 Maple Drive"
end

@testset "is_po_box" begin
    @test is_po_box("P.O. Box 123")
    @test is_po_box("PO Box 456")
    @test is_po_box("P O Box 789")
    @test is_po_box("Post Office Box 100")
    @test !is_po_box("123 Main Street")
    @test !is_po_box("1234 Box Elder Drive")
end

@testset "is_rural_route" begin
    @test is_rural_route("RR 1")
    @test is_rural_route("RR 2 Box 45")
    @test is_rural_route("Rural Route 3")
    @test is_rural_route("HC 61 Box 10")
    @test is_rural_route("General Delivery")
    @test !is_rural_route("123 Main Street")
end

@testset "standardize_state" begin
    @test standardize_state("ND") == "ND"
    @test standardize_state("North Dakota") == "ND"
    @test standardize_state("north dakota") == "ND"
    @test standardize_state("California") == "CA"
    @test standardize_state("TX") == "TX"
    @test standardize_state("UNKNOWN STATE") == "UNKNOWN STATE"  # pass through
end

@testset "GeocodedAddress struct" begin
    ga = GeocodedAddress("1", "123 Main St, Fargo, ND", "123 Main Street, Fargo, ND 58102",
                          46.8772, -96.7898, "Match", "38017950100", 95.0, :census)
    @test ga.lat ≈ 46.8772
    @test ga.lon ≈ -96.7898
    @test ga.match_type == "Match"
    @test ga.backend == :census
    @test ga.score == 95.0
    @test length(ga.tract_fips) == 11
end

@testset "CensusGeocoder struct" begin
    g = CensusGeocoder()
    @test g.vintage == "Current"
    g2 = CensusGeocoder(; vintage="Census2020")
    @test g2.vintage == "Census2020"
end

@testset "NominatimGeocoder requires user-agent" begin
    @test_throws ErrorException NominatimGeocoder(; user_agent="")
    g = NominatimGeocoder(; user_agent="TestApp/1.0")
    @test g.user_agent == "TestApp/1.0"
    @test g.sleep_sec ≈ 1.1
end

@testset "geocode_all Census (network; skipped if unavailable)" begin
    addresses = DataFrame(
        id     = ["1", "2"],
        street = ["600 E Boulevard Dr", "1600 Pennsylvania Ave NW"],
        city   = ["Bismarck", "Washington"],
        state  = ["ND", "DC"],
        zip    = ["58505", "20500"],
    )
    try
        results = geocode_all(addresses; backend=CensusGeocoder(), batch_size=500)
        @test nrow(results) == 2
        @test "lat" ∈ names(results)
        @test "lon" ∈ names(results)
    catch e
        @warn "Census geocoder network test skipped: $e"
    end
end
