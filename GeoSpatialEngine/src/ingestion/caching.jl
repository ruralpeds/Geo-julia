"""
Caching system for geospatial data.
"""

"""
    CacheManager

Manager for caching geospatial data.

# Fields
- `cache_dir::String`: Cache directory path
- `max_age::Float64`: Maximum cache age in seconds
"""
struct CacheManager
    cache_dir::String
    max_age::Float64

    function CacheManager(cache_dir::String; max_age::Float64=3600.0)
        if !isdir(cache_dir)
            mkpath(cache_dir)
        end
        new(cache_dir, max_age)
    end
end

"""
    save_to_cache(cache_manager::CacheManager, key::String, data::GeoSpatialData)

Save geospatial data to cache.

# Arguments
- `cache_manager::CacheManager`: Cache manager instance
- `key::String`: Cache key
- `data::GeoSpatialData`: Data to cache
"""
function save_to_cache(cache_manager::CacheManager, key::String, data::GeoSpatialData)
    cache_file = joinpath(cache_manager.cache_dir, "$(key).jld2")

    try
        using JLD2
        jldopen(cache_file, "w") do file
            file["data"] = data
            file["timestamp"] = now(UTC)
        end
        @info "Data cached: $key"
    catch e
        @warn "Failed to cache data: $e"
    end
end

"""
    load_from_cache(cache_manager::CacheManager, key::String)

Load cached geospatial data.

# Arguments
- `cache_manager::CacheManager`: Cache manager instance
- `key::String`: Cache key

# Returns
- `Union{GeoSpatialData, Nothing}`: Cached data or nothing if not found/expired
"""
function load_from_cache(cache_manager::CacheManager, key::String)
    cache_file = joinpath(cache_manager.cache_dir, "$(key).jld2")

    if !isfile(cache_file)
        return nothing
    end

    try
        using JLD2
        jldopen(cache_file, "r") do file
            timestamp = file["timestamp"]
            age = (now(UTC) - timestamp).value / 1000  # Convert to seconds

            if age > cache_manager.max_age
                @debug "Cache expired for key: $key"
                return nothing
            end

            return file["data"]
        end
    catch e
        @warn "Failed to load from cache: $e"
        return nothing
    end
end

"""
    clear_cache(cache_manager::CacheManager)

Clear all cached data.
"""
function clear_cache(cache_manager::CacheManager)
    for file in readdir(cache_manager.cache_dir)
        try
            rm(joinpath(cache_manager.cache_dir, file))
        catch e
            @warn "Failed to delete cache file: $file"
        end
    end
    @info "Cache cleared"
end

"""
    get_cache_info(cache_manager::CacheManager)

Get information about cache status.

# Returns
- `Dict`: Cache statistics
"""
function get_cache_info(cache_manager::CacheManager)
    files = readdir(cache_manager.cache_dir)
    total_size = sum(filesize(joinpath(cache_manager.cache_dir, f)) for f in files)

    return Dict(
        "cache_dir" => cache_manager.cache_dir,
        "num_files" => length(files),
        "total_size_bytes" => total_size,
        "total_size_mb" => total_size / (1024^2)
    )
end
