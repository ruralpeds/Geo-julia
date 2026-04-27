"""
Nominatim geocoding client (OpenStreetMap).

Nominatim is a free geocoding service that doesn't require an API key.
Used as fallback when Census API is unavailable or rate limited.
"""

const NOMINATIM_API_URL = "https://nominatim.openstreetmap.org/search"
const NOMINATIM_RATE_LIMITER = RateLimiter(1.0)  # 1 request per second (per Nominatim policy)

"""
    geocode_nominatim(address::String) -> GeocodeResult

Geocode a single address using Nominatim API.

# Arguments
- `address::String`: Address to geocode

# Returns
GeocodeResult with Nominatim match

# Details
- Requires user agent header (per Nominatim terms)
- Rate limited to 1 request/second
- Returns approximate location if exact match not available
"""
function geocode_nominatim(address::String)::GeocodeResult
    # Apply rate limiting
    acquire!(NOMINATIM_RATE_LIMITER)

    standardized = standardize_address(address)

    try
        headers = [
            "User-Agent" => "Geocode.jl/0.1.0 (+https://github.com/timothyhartzog/geocode)"
        ]

        params = Dict(
            "q" => standardized,
            "format" => "json",
            "limit" => "1"
        )

        response = HTTP.get(
            NOMINATIM_API_URL,
            headers;
            query=params,
            timeout=10.0
        )

        if response.status != 200
            error_msg = extract_error_message(response)
            return GeocodeResult(address, error_msg)
        end

        response_data = JSON.parse(String(response.body))
        return parse_nominatim_response(response_data, address)

    catch e
        error_msg = "Nominatim error: $(string(e))"
        @warn error_msg
        return GeocodeResult(address, error_msg)
    end
end

"""
    geocode_nominatim_batch(addresses::Vector{String}; delay::Float64=1.0) -> Vector{GeocodeResult}

Geocode multiple addresses using Nominatim (respecting rate limits).

# Arguments
- `addresses::Vector{String}`: Addresses to geocode
- `delay::Float64`: Delay between requests in seconds (min 1.0 per Nominatim policy)

# Returns
Vector of GeocodeResult objects
"""
function geocode_nominatim_batch(addresses::Vector{String}; delay::Float64=1.0)::Vector{GeocodeResult}
    delay = max(delay, 1.0)  # Enforce minimum delay
    results = GeocodeResult[]

    for (i, addr) in enumerate(addresses)
        result = geocode_nominatim(addr)
        push!(results, result)

        # Add delay between requests (Nominatim policy)
        if i < length(addresses)
            sleep(delay)
        end
    end

    return results
end

"""
    can_use_nominatim() -> Bool

Check if Nominatim service is available (performs health check).
"""
function can_use_nominatim()::Bool
    try
        acquire!(NOMINATIM_RATE_LIMITER)

        headers = [
            "User-Agent" => "Geocode.jl/0.1.0 (+https://github.com/timothyhartzog/geocode)"
        ]

        # Simple health check with a known address
        params = Dict(
            "q" => "1 osm house",
            "format" => "json",
            "limit" => "1"
        )

        response = HTTP.get(
            NOMINATIM_API_URL,
            headers;
            query=params,
            timeout=5.0
        )

        return response.status == 200
    catch e
        @warn "Nominatim health check failed: $(string(e))"
        return false
    end
end
