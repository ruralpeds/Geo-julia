"""
    GeocodeResult

Result from a geocoding operation.

# Fields
- `address::String`: The input address
- `latitude::Float64`: Latitude of matched location
- `longitude::Float64`: Longitude of matched location
- `match_quality::QualityLevel`: Quality of the match
- `source::String`: Source API (Census, Nominatim, Cache)
- `timestamp::DateTime`: When the result was obtained
- `matched_address::String`: The actual matched address from API
- `error::Union{String, Nothing}`: Error message if geocoding failed
"""
mutable struct GeocodeResult
    address::String
    latitude::Float64
    longitude::Float64
    match_quality::QualityLevel
    source::String
    timestamp::DateTime
    matched_address::String
    error::Union{String, Nothing}
end

"""
    CensusMatch

Census API match metadata.

# Fields
- `match_indicator::String`: Match type (Rooftop, Range, Street, City)
- `tigerline_id::String`: TIGER/Line ID from Census
- `side::Union{String, Nothing}`: Side of street (L or R)
"""
struct CensusMatch
    match_indicator::String
    tigerline_id::String
    side::Union{String, Nothing}
end

"""
    GeocodeResult(address; latitude, longitude, quality, source, matched_address)

Convenience constructor for successful geocode results.
"""
function GeocodeResult(address::String, latitude::Real, longitude::Real,
                      quality::QualityLevel, source::String, matched_address::String="")
    GeocodeResult(
        address,
        Float64(latitude),
        Float64(longitude),
        quality,
        source,
        now(UTC),
        matched_address,
        nothing
    )
end

"""
    GeocodeResult(address, error::String)

Convenience constructor for failed geocoding with error message.
"""
function GeocodeResult(address::String, error::String)
    GeocodeResult(
        address,
        NaN,
        NaN,
        UNKNOWN,
        "error",
        now(UTC),
        "",
        error
    )
end

Base.show(io::IO, result::GeocodeResult) = print(io,
    "GeocodeResult(address=\"$(result.address)\", " *
    "lat=$(result.latitude), lon=$(result.longitude), " *
    "quality=$(result.match_quality), source=\"$(result.source)\")")
