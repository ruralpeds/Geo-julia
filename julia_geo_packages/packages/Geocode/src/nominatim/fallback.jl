"""
Quality-aware fallback logic for geocoding.

When Census API fails or returns low-quality matches, automatically
fall back to Nominatim for best-effort results.
"""

"""
    should_fallback_to_nominatim(result::GeocodeResult) -> Bool

Determine if we should retry with Nominatim based on Census result quality.

# Fallback conditions:
- Result is an error
- Match quality is unknown (no match found)
- Result timed out
"""
function should_fallback_to_nominatim(result::GeocodeResult)::Bool
    # Error results should trigger fallback
    if result.error !== nothing
        return !contains(result.error, "rate limit")  # Don't fallback on rate limit
    end

    # Unknown quality matches should retry
    if result.match_quality == UNKNOWN
        return true
    end

    return false
end

"""
    geocode_with_fallback(address::String; api_key::String="", use_fallback::Bool=true) -> GeocodeResult

Geocode an address with automatic fallback to Nominatim if Census fails.

# Arguments
- `address::String`: Address to geocode
- `api_key::String`: Census API key
- `use_fallback::Bool`: Whether to use Nominatim fallback (default true)

# Returns
GeocodeResult (best match from Census or Nominatim)

# Strategy
1. Try Census API (if key available)
2. If Census fails/no match, try Nominatim
3. Return best result (Census preferred if both available)
"""
function geocode_with_fallback(address::String; api_key::String="", use_fallback::Bool=true)::GeocodeResult
    # Check cache first
    cached = get_cached_result(address)
    if cached !== nothing
        return cached
    end

    best_result = nothing
    census_attempted = false

    # Try Census if key available
    if !isempty(api_key) || haskey(ENV, "CENSUS_API_KEY") || isfile(joinpath(homedir(), ".geocode_census_key"))
        try
            census_result = geocode_single_census(address; api_key=api_key)
            census_attempted = true
            best_result = census_result

            # If Census succeeded, cache and return
            if census_result.error === nothing && census_result.match_quality != UNKNOWN
                cache_result(census_result)
                return census_result
            end
        catch e
            @debug "Census geocoding failed: $e"
        end
    end

    # Fall back to Nominatim if Census failed/unavailable
    if use_fallback && (best_result === nothing || should_fallback_to_nominatim(best_result))
        if can_use_nominatim()
            nominatim_result = geocode_nominatim(address)
            best_result = nominatim_result

            if nominatim_result.error === nothing
                cache_result(nominatim_result)
                return nominatim_result
            end
        end
    end

    # Return best result we have, or error
    if best_result !== nothing
        cache_result(best_result)
        return best_result
    else
        error_result = GeocodeResult(address, "All geocoding services failed")
        return error_result
    end
end

"""
    compare_results(census::GeocodeResult, nominatim::GeocodeResult) -> GeocodeResult

Compare two results and return the higher quality one.

# Comparison logic:
1. Prefer results with coordinates
2. Prefer higher quality level
3. Prefer Census if equal quality
"""
function compare_results(census::GeocodeResult, nominatim::GeocodeResult)::GeocodeResult
    # Filter out errors
    if census.error === nothing && nominatim.error !== nothing
        return census
    end
    if nominatim.error === nothing && census.error !== nothing
        return nominatim
    end
    if census.error !== nothing && nominatim.error !== nothing
        return census  # Prefer Census even if both failed (more detailed error)
    end

    # Both succeeded - compare quality
    if Int(census.match_quality) > Int(nominatim.match_quality)
        return census
    elseif Int(nominatim.match_quality) > Int(census.match_quality)
        return nominatim
    else
        # Equal quality - prefer Census
        return census
    end
end

"""
    batch_geocode_with_fallback(addresses::Vector{String};
                                 api_key::String="",
                                 use_fallback::Bool=true,
                                 show_progress::Bool=true) -> Vector{GeocodeResult}

Batch geocode multiple addresses with fallback support.

# Arguments
- `addresses::Vector{String}`: Addresses to geocode
- `api_key::String`: Census API key
- `use_fallback::Bool`: Use Nominatim fallback (default true)
- `show_progress::Bool`: Show progress bar (default true)

# Returns
Vector of GeocodeResult objects
"""
function batch_geocode_with_fallback(addresses::Vector{String};
                                     api_key::String="",
                                     use_fallback::Bool=true,
                                     show_progress::Bool=true)::Vector{GeocodeResult}
    results = GeocodeResult[]

    # Deduplicate addresses for efficiency
    dedup = deduplicate_addresses(addresses)

    # Track which addresses need Census retry for Nominatim
    census_failures = String[]

    # Process Census API if available
    if !isempty(api_key) || haskey(ENV, "CENSUS_API_KEY") || isfile(joinpath(homedir(), ".geocode_census_key"))
        unique_addresses = collect(keys(dedup))

        if show_progress
            pbar = Progress(length(unique_addresses), desc="Census geocoding")
        end

        census_results = geocode_census(unique_addresses; api_key=api_key)

        for result in census_results
            push!(results, result)

            # Track failures for Nominatim fallback
            if should_fallback_to_nominatim(result)
                push!(census_failures, result.address)
            end

            if show_progress
                next!(pbar)
            end
        end

        if show_progress
            finish!(pbar)
        end
    else
        # No Census key - all addresses need Nominatim
        census_failures = collect(keys(deduplicate_addresses(addresses)))
    end

    # Fall back to Nominatim for failures
    if use_fallback && !isempty(census_failures) && can_use_nominatim()
        if show_progress
            pbar = Progress(length(census_failures), desc="Nominatim fallback")
        end

        for addr in census_failures
            result = geocode_nominatim(addr)
            push!(results, result)

            if show_progress
                next!(pbar)
            end
        end

        if show_progress
            finish!(pbar)
        end
    end

    # Cache all successful results
    for result in results
        if result.error === nothing
            cache_result(result)
        end
    end

    return results
end
