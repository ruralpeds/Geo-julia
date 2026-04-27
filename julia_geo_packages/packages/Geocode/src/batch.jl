"""
Batch geocoding with progress tracking and caching.
"""

"""
    batch_geocode(addresses::Union{Vector{String}, DataFrame};
                   api_key::String="",
                   batch_size::Int=100,
                   retry::Int=3,
                   use_fallback::Bool=true,
                   show_progress::Bool=true) -> Vector{GeocodeResult}

Batch geocode addresses with automatic caching and fallback.

# Arguments
- `addresses::Union{Vector{String}, DataFrame}`: Addresses to geocode
  - If DataFrame, uses first column as addresses
- `api_key::String`: Census API key
- `batch_size::Int`: Batch size for Census API (max 100, default 100)
- `retry::Int`: Number of retries for failed addresses (default 3)
- `use_fallback::Bool`: Use Nominatim fallback (default true)
- `show_progress::Bool`: Show progress bar (default true)

# Returns
Vector of GeocodeResult objects in same order as input

# Features
- Automatic cache checking (skips already-cached addresses)
- Rate limiting (10 req/sec for Census, 1 req/sec for Nominatim)
- Progress bar for large batches
- Retry logic for transient failures
- DataFrame input/output support

# Examples
```julia
# From vector of strings
results = batch_geocode(["123 Main St, NYC", "456 Oak Ave, LA"])

# From DataFrame
df = DataFrame(address=["123 Main St", "456 Oak Ave"])
results = batch_geocode(df)

# With custom API key and retries
results = batch_geocode(addresses; api_key="key123", retry=5)

# Without fallback (Census only)
results = batch_geocode(addresses; use_fallback=false)
```
"""
function batch_geocode(addresses::Union{Vector{String}, DataFrame};
                       api_key::String="",
                       batch_size::Int=100,
                       retry::Int=3,
                       use_fallback::Bool=true,
                       show_progress::Bool=true)::Vector{GeocodeResult}

    # Convert DataFrame to vector of strings
    if isa(addresses, DataFrame)
        if nrow(addresses) == 0
            return GeocodeResult[]
        end
        col_name = names(addresses)[1]
        address_vec = string.(addresses[!, col_name])
    else
        address_vec = string.(addresses)
    end

    if isempty(address_vec)
        return GeocodeResult[]
    end

    # Clamp batch size
    batch_size = min(max(batch_size, 1), 100)

    # Results in order of input
    results = Dict{String, GeocodeResult}()

    # First pass: check cache
    to_geocode = String[]
    for addr in address_vec
        if haskey(results, addr)
            continue  # Already have result
        end

        cached = get_cached_result(addr)
        if cached !== nothing
            results[addr] = cached
        else
            push!(to_geocode, addr)
        end
    end

    if show_progress && !isempty(to_geocode)
        pbar = Progress(length(to_geocode), desc="Geocoding addresses")
    end

    # Process remaining addresses in batches
    for attempt in 1:retry
        if isempty(to_geocode)
            break
        end

        batch_results = geocode_with_fallback.(to_geocode;
                                              api_key=api_key,
                                              use_fallback=use_fallback)

        for result in batch_results
            results[result.address] = result

            if show_progress
                next!(pbar)
            end

            # Cache successful results
            if result.error === nothing && result.match_quality != UNKNOWN
                cache_result(result)
            end
        end

        # Identify addresses that still failed for retry
        to_geocode = [addr for addr in to_geocode
                      if haskey(results, addr) &&
                         (results[addr].error !== nothing ||
                          results[addr].match_quality == UNKNOWN)]

        if isempty(to_geocode) || attempt == retry
            break
        end

        # Brief pause before retry
        sleep(0.5)
    end

    if show_progress && !isempty(address_vec)
        finish!(pbar)
    end

    # Return results in input order
    final_results = GeocodeResult[]
    for addr in address_vec
        push!(final_results, results[addr])
    end

    return final_results
end

"""
    batch_geocode_to_dataframe(addresses::Union{Vector{String}, DataFrame};
                               api_key::String="",
                               batch_size::Int=100,
                               retry::Int=3,
                               use_fallback::Bool=true,
                               show_progress::Bool=true) -> DataFrame

Batch geocode and return results as a DataFrame.

# Returns
DataFrame with columns: address, latitude, longitude, match_quality, source, matched_address, error
"""
function batch_geocode_to_dataframe(addresses::Union{Vector{String}, DataFrame};
                                    api_key::String="",
                                    batch_size::Int=100,
                                    retry::Int=3,
                                    use_fallback::Bool=true,
                                    show_progress::Bool=true)::DataFrame

    results = batch_geocode(addresses;
                           api_key=api_key,
                           batch_size=batch_size,
                           retry=retry,
                           use_fallback=use_fallback,
                           show_progress=show_progress)

    # Convert results to DataFrame
    return DataFrame(
        address=[r.address for r in results],
        latitude=[r.latitude for r in results],
        longitude=[r.longitude for r in results],
        match_quality=[string(r.match_quality) for r in results],
        source=[r.source for r in results],
        matched_address=[r.matched_address for r in results],
        error=[r.error for r in results],
        timestamp=[r.timestamp for r in results]
    )
end

"""
    geocode(address::String; api_key::String="", use_fallback::Bool=true) -> GeocodeResult

Geocode a single address.

# Arguments
- `address::String`: Address to geocode
- `api_key::String`: Census API key
- `use_fallback::Bool`: Use Nominatim fallback

# Returns
GeocodeResult with coordinates and quality level

# Example
```julia
result = geocode("123 Main St, New York, NY")
if result.error === nothing
    println("Location: (\$(result.latitude), \$(result.longitude))")
end
```
"""
function geocode(address::String; api_key::String="", use_fallback::Bool=true)::GeocodeResult
    geocode_with_fallback(address; api_key=api_key, use_fallback=use_fallback)
end
