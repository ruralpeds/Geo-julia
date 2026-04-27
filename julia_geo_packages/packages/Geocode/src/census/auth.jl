"""
Census API authentication and key management.
"""

"""
    get_api_key(key::Union{String, Nothing}=nothing) -> String

Get the Census API key. Uses provided key, ENV var, or ~/.geocode_census_key file.

# Arguments
- `key::Union{String, Nothing}`: Override API key (if provided, uses this)

# Priority order:
1. Provided `key` parameter
2. ENV[\"CENSUS_API_KEY\"]
3. \~/.geocode_census_key file
4. Error if none found

# Raises
RuntimeError if no API key found
"""
function get_api_key(key::Union{String, Nothing}=nothing)::String
    # Use provided key if given
    if key !== nothing && !isempty(strip(key))
        return strip(key)
    end

    # Check environment variable
    if haskey(ENV, "CENSUS_API_KEY")
        env_key = get(ENV, "CENSUS_API_KEY", "")
        if !isempty(strip(env_key))
            return strip(env_key)
        end
    end

    # Check ~/.geocode_census_key file
    key_file = joinpath(homedir(), ".geocode_census_key")
    if isfile(key_file)
        try
            key_content = strip(read(key_file, String))
            if !isempty(key_content)
                return key_content
            end
        catch e
            @warn "Error reading API key file: $e"
        end
    end

    # No key found
    error(
        "Census API key not found. " *
        "Provide via key parameter, CENSUS_API_KEY environment variable, " *
        "or ~/.geocode_census_key file"
    )
end

"""
    validate_api_key(key::String) -> Bool

Validate that the API key format is correct (non-empty, reasonable length).
"""
function validate_api_key(key::String)::Bool
    !isempty(strip(key)) && length(key) >= 10
end
