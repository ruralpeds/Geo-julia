"""
Parse Census Batch Geocoder API responses.
"""

"""
    parse_census_response(json_data::Dict) -> Vector{GeocodeResult}

Parse Census Batch Geocoder API response and return geocode results.

The Census API returns an array of result objects with:
- result.addressMatches[]: array of matches
- result.addressMatches[].matchedAddress: matched address string
- result.addressMatches[].coordinates: {x: lon, y: lat}
- result.addressMatches[].tigerLineId: TIGER line ID
- result.addressMatches[].side: L or R (side of street)
- result.tigerLineId: TIGER line ID from input
- result.addressComponents: {street, city, state, zip}

# Returns
Vector of GeocodeResult objects
"""
function parse_census_response(json_data::Dict, address::String)::GeocodeResult
    # Handle error response
    if haskey(json_data, "errors") && length(json_data["errors"]) > 0
        error_msg = get(json_data["errors"][1], "message", "Unknown error")
        return GeocodeResult(address, error_msg)
    end

    # Extract matches
    matches = get(json_data, "addressMatches", [])

    if isempty(matches)
        return GeocodeResult(address, "No matches found")
    end

    # Use the best match (first one, ranked by Census)
    match = matches[1]

    # Extract coordinates
    coords = get(match, "coordinates", Dict())
    lat = get(coords, "y", NaN)
    lon = get(coords, "x", NaN)

    if isnan(lat) || isnan(lon)
        return GeocodeResult(address, "Invalid coordinates in response")
    end

    # Extract match quality indicator
    matched_address = get(match, "matchedAddress", "")
    tiger_id = get(match, "tigerLineId", "")

    # Determine quality level from match properties
    quality = determine_match_quality(match)

    return GeocodeResult(
        address,
        lat,
        lon,
        quality,
        "census",
        matched_address
    )
end

"""
    determine_match_quality(match::Dict) -> QualityLevel

Determine quality level from Census match metadata.

Census provides several quality indicators:
- exact rooftop match
- address range interpolation
- street centroid
- city centroid
"""
function determine_match_quality(match::Dict)::QualityLevel
    # Check for explicit match indicator
    if haskey(match, "addressType")
        return parse_quality_indicator(match["addressType"])
    end

    # Check matchedAddress format for clues
    matched = get(match, "matchedAddress", "")

    # Heuristics based on Census response patterns
    # More specific matches appear higher quality in the response
    if !isempty(matched)
        # If we got coordinates and a full address, likely at least street-level
        return STREET
    end

    return UNKNOWN
end

"""
    parse_nominatim_response(json_data::Vector) -> GeocodeResult

Parse Nominatim API response (returns array of results).

Nominatim response format:
```json
[
  {
    "place_id": 12345,
    "lat": "40.7128",
    "lon": "-74.0060",
    "class": "place",
    "type": "city",
    "display_name": "New York, United States"
  }
]
```
"""
function parse_nominatim_response(json_data::Vector, address::String)::GeocodeResult
    if isempty(json_data)
        return GeocodeResult(address, "No matches found")
    end

    match = json_data[1]

    # Extract coordinates
    try
        lat = parse(Float64, match["lat"])
        lon = parse(Float64, match["lon"])

        if !is_valid_coordinate(lat, lon)
            return GeocodeResult(address, "Invalid coordinates in response")
        end

        # Determine quality from Nominatim type
        matched_address = get(match, "display_name", "")
        match_type = get(match, "type", "unknown")
        match_class = get(match, "class", "unknown")

        quality = determine_nominatim_quality(match_type, match_class)

        return GeocodeResult(
            address,
            lat,
            lon,
            quality,
            "nominatim",
            matched_address
        )
    catch e
        return GeocodeResult(address, "Error parsing coordinates: $e")
    end
end

"""
    determine_nominatim_quality(match_type::String, match_class::String) -> QualityLevel

Determine quality level from Nominatim match type and class.
"""
function determine_nominatim_quality(match_type::String, match_class::String)::QualityLevel
    match_type = lowercase(match_type)
    match_class = lowercase(match_class)

    # High quality types
    if match_type in ["house", "street", "building"]
        return STREET
    end

    if match_class in ["place"]
        if match_type in ["city", "village", "town", "municipality"]
            return CITY
        end
    end

    # Medium quality
    if match_class in ["boundary"]
        return CITY
    end

    return STREET  # Default to street if we got a match
end

"""
    extract_error_message(response::HTTP.Response) -> String

Extract error message from HTTP response.
"""
function extract_error_message(response::HTTP.Response)::String
    status = response.status

    if status == 400
        return "Bad request (invalid address format)"
    elseif status == 401
        return "Unauthorized (invalid API key)"
    elseif status == 403
        return "Forbidden (rate limit exceeded)"
    elseif status == 404
        return "Not found"
    elseif status == 500
        return "Server error (Census service unavailable)"
    elseif status == 503
        return "Service unavailable"
    else
        return "HTTP $status"
    end
end
