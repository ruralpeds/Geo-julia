"""
    standardize_address(address::String) -> String

Standardize an address by normalizing whitespace, case, and removing extra characters.

# Examples
```julia
standardize_address("123  Main  ST., NEW YORK, NY 10001")
# Returns: "123 main st new york ny 10001"
```
"""
function standardize_address(address::String)
    # Convert to lowercase
    addr = lowercase(address)

    # Remove extra whitespace
    addr = strip(addr)
    addr = replace(addr, r"\s+" => " ")

    # Remove common abbreviation punctuation
    addr = replace(addr, "." => "")
    addr = replace(addr, "," => "")

    # Remove special characters except spaces and alphanumerics
    addr = replace(addr, r"[^\w\s]" => "")

    return addr
end

"""
    address_hash(address::String) -> String

Generate a deterministic hash for cache key lookups.
"""
function address_hash(address::String)
    standardized = standardize_address(address)
    string(abs(hash(standardized)))
end

"""
    deduplicate_addresses(addresses::Vector{String}) -> Dict{String, Int}

Return dict of unique addresses with original indices.

# Returns
Dictionary mapping unique (standardized) addresses to count of occurrences.
"""
function deduplicate_addresses(addresses::Vector{String})
    dedup = Dict{String, Vector{Int}}()

    for (idx, addr) in enumerate(addresses)
        std_addr = standardize_address(addr)
        if !haskey(dedup, std_addr)
            dedup[std_addr] = Int[]
        end
        push!(dedup[std_addr], idx)
    end

    return dedup
end

"""
    parse_quality_indicator(indicator::String) -> QualityLevel

Parse Census match indicator into QualityLevel.
"""
function parse_quality_indicator(indicator::String)::QualityLevel
    lower_ind = lowercase(indicator)

    if contains(lower_ind, "rooftop")
        return ROOFTOP
    elseif contains(lower_ind, "range")
        return RANGE
    elseif contains(lower_ind, "street")
        return STREET
    elseif contains(lower_ind, "city")
        return CITY
    else
        return UNKNOWN
    end
end

"""
    is_valid_coordinate(lat::Real, lon::Real) -> Bool

Validate that coordinates are valid (not NaN, in valid ranges).
"""
function is_valid_coordinate(lat::Real, lon::Real)::Bool
    !isnan(lat) && !isnan(lon) &&
    -90.0 <= lat <= 90.0 &&
    -180.0 <= lon <= 180.0
end

"""
    parse_address_parts(address::String) -> NamedTuple

Parse address into components (street, city, state, zip).

Very basic parser—assumes format: "street, city, state zip" or variations.
"""
function parse_address_parts(address::String)
    parts = split(address, ',')

    street = length(parts) > 0 ? strip(parts[1]) : ""
    city = length(parts) > 1 ? strip(parts[2]) : ""
    state = ""
    zip = ""

    if length(parts) > 2
        remaining = strip(parts[3])
        # Try to split state and zip
        pieces = split(remaining)
        if length(pieces) >= 2
            state = pieces[1]
            zip = pieces[2]
        elseif length(pieces) == 1
            state = pieces[1]
        end
    end

    return (street=street, city=city, state=state, zip=zip)
end

"""
    format_census_query(address::String, city::String, state::String, zip::String) -> String

Format query string for Census Batch API.
"""
function format_census_query(address::String; city::String="", state::String="", zip::String="")
    parts = String[]
    push!(parts, address)
    !isempty(city) && push!(parts, city)
    !isempty(state) && push!(parts, state)
    !isempty(zip) && push!(parts, zip)
    join(parts, ", ")
end
