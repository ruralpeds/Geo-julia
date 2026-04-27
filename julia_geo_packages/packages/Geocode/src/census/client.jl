"""
Census Batch Geocoder API client with rate limiting.
"""

# Token bucket for rate limiting
struct RateLimiter
    tokens::Ref{Float64}
    max_tokens::Float64
    refill_rate::Float64  # tokens per second
    last_refill::Ref{Float64}
    lock::ReentrantLock
end

"""
    RateLimiter(requests_per_sec::Real) -> RateLimiter

Create a token bucket rate limiter.

# Arguments
- `requests_per_sec`: Maximum requests per second (default 10 for Census API)
"""
function RateLimiter(requests_per_sec::Real=10.0)
    RateLimiter(
        Ref(requests_per_sec),  # Start with full tokens
        requests_per_sec,
        requests_per_sec,
        Ref(time()),
        ReentrantLock()
    )
end

"""
    acquire!(limiter::RateLimiter)

Wait until a token is available, then consume it.
"""
function acquire!(limiter::RateLimiter)
    lock(limiter.lock) do
        while true
            now_time = time()
            elapsed = now_time - limiter.last_refill[]

            # Refill tokens based on elapsed time
            new_tokens = min(
                limiter.max_tokens,
                limiter.tokens[] + elapsed * limiter.refill_rate
            )
            limiter.tokens[] = new_tokens
            limiter.last_refill[] = now_time

            if limiter.tokens[] >= 1.0
                limiter.tokens[] -= 1.0
                return
            end

            # Wait a bit before trying again
            sleep(0.01)
        end
    end
end

const CENSUS_API_URL = "https://geocoding.geo.census.gov/geocoder/geographies/batchgeocode"
const CENSUS_RATE_LIMITER = RateLimiter(10.0)  # 10 requests per second

"""
    geocode_census(addresses::Vector{String}; api_key::String="") -> Vector{GeocodeResult}

Batch geocode addresses using Census Batch Geocoder API.

# Arguments
- `addresses::Vector{String}`: List of addresses to geocode
- `api_key::String`: Census API key (or from environment/file)

# Returns
Vector of GeocodeResult objects

# Details
Uses Census Batch Geocoder which accepts up to 10,000 addresses per request.
Implements rate limiting (10 requests/sec) to avoid hitting API limits.
"""
function geocode_census(addresses::Vector{String}; api_key::String="")::Vector{GeocodeResult}
    api_key = get_api_key(api_key)

    if !validate_api_key(api_key)
        error("Invalid Census API key format")
    end

    results = GeocodeResult[]

    # Process in batches (Census recommends <= 10,000 per request)
    batch_size = 100
    for i in 1:batch_size:length(addresses)
        batch_end = min(i + batch_size - 1, length(addresses))
        batch = addresses[i:batch_end]

        batch_results = geocode_census_batch(batch, api_key)
        append!(results, batch_results)

        # Brief pause between batches even with rate limiting
        if batch_end < length(addresses)
            sleep(0.1)
        end
    end

    return results
end

"""
    geocode_census_batch(addresses::Vector{String}, api_key::String) -> Vector{GeocodeResult}

Geocode a single batch of addresses via Census API.
"""
function geocode_census_batch(addresses::Vector{String}, api_key::String)::Vector{GeocodeResult}
    # Wait for rate limit token
    acquire!(CENSUS_RATE_LIMITER)

    # Build benchmark data format
    # Census expects tab-separated: id, street, city, state, zip
    benchmark_data = String[]

    for (i, addr) in enumerate(addresses)
        # Simple format: use address number and full address
        push!(benchmark_data, "$(i)\t$addr")
    end

    request_body = join(benchmark_data, "\n")

    try
        # Send request
        headers = ["Content-Type" => "text/plain"]
        params = Dict(
            "benchmark" => "Public_AR_Current",
            "format" => "json",
            "key" => api_key
        )

        response = HTTP.post(
            CENSUS_API_URL,
            headers,
            request_body;
            query=params,
            timeout=30.0
        )

        if response.status != 200
            error_msg = extract_error_message(response)
            @warn "Census API error: $error_msg"
            # Return error results for all addresses
            return [GeocodeResult(addr, error_msg) for addr in addresses]
        end

        # Parse response
        response_data = JSON.parse(String(response.body))

        return process_census_batch_response(response_data, addresses)

    catch e
        # Timeout or connection error
        error_msg = "Census API error: $(string(e))"
        @warn error_msg
        return [GeocodeResult(addr, error_msg) for addr in addresses]
    end
end

"""
    process_census_batch_response(response_data::Dict, addresses::Vector{String}) -> Vector{GeocodeResult}

Process Census API batch response.
"""
function process_census_batch_response(response_data::Dict, addresses::Vector{String})::Vector{GeocodeResult}
    results = GeocodeResult[]

    # Census returns results array
    results_array = get(response_data, "result", Dict())
    result_matches = get(results_array, "addressMatches", [])

    if isempty(result_matches)
        # No matches at all
        return [GeocodeResult(addr, "No matches found") for addr in addresses]
    end

    # Create a map of result index to result object
    result_dict = Dict{Int, Dict}()
    for match in result_matches
        input_id = get(match, "inputId", nothing)
        if input_id !== nothing
            result_dict[input_id] = match
        end
    end

    # Process each address in order
    for (i, addr) in enumerate(addresses)
        if haskey(result_dict, i)
            match_data = result_dict[i]
            result = parse_census_response(Dict("addressMatches" => [match_data]), addr)
        else
            result = GeocodeResult(addr, "No match found in Census response")
        end
        push!(results, result)
    end

    return results
end

"""
    geocode_single_census(address::String; api_key::String="") -> GeocodeResult

Geocode a single address using Census API.
"""
function geocode_single_census(address::String; api_key::String="")::GeocodeResult
    results = geocode_census([address]; api_key=api_key)
    return results[1]
end
