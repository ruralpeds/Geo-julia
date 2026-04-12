"""
Configuration management for GeoSpatialEngine.
"""

function load_config(config_file::String)
    @info "Loading configuration from: $config_file"
    if !isfile(config_file)
        @warn "Configuration file not found: $config_file"
        return GeoEngineConfig()
    end

    config_data = JSON.parsefile(config_file)
    config = GeoEngineConfig(
        cache_enabled = get(config_data, "cache_enabled", true),
        cache_dir = get(config_data, "cache_dir", ".geo_cache"),
        parallel_processing = get(config_data, "parallel_processing", true),
        num_workers = get(config_data, "num_workers", Threads.nthreads()),
        timeout = get(config_data, "timeout", 30.0),
        log_level = get(config_data, "log_level", "Info")
    )

    return config
end

function save_config(config::GeoEngineConfig, config_file::String)
    @info "Saving configuration to: $config_file"
    config_dict = Dict(
        "cache_enabled" => config.cache_enabled,
        "cache_dir" => config.cache_dir,
        "parallel_processing" => config.parallel_processing,
        "num_workers" => config.num_workers,
        "timeout" => config.timeout,
        "log_level" => config.log_level
    )

    open(config_file, "w") do f
        JSON.print(f, config_dict)
    end
end

function update_config!(config::GeoEngineConfig; kwargs...)
    for (key, value) in kwargs
        if hasproperty(config, key)
            setproperty!(config, key, value)
        end
    end
    @info "Configuration updated"
    return config
end

function validate_config(config::GeoEngineConfig)
    issues = String[]

    if config.num_workers <= 0
        push!(issues, "num_workers must be positive")
    end

    if config.timeout <= 0
        push!(issues, "timeout must be positive")
    end

    if !(config.log_level in ["Debug", "Info", "Warn", "Error"])
        push!(issues, "Invalid log_level")
    end

    if isempty(issues)
        @info "Configuration is valid"
        return true
    else
        @warn "Configuration issues: $(join(issues, ", "))"
        return false
    end
end
