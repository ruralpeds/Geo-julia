"""
Registry and management of geospatial data sources.
"""

"""
    DataSourceRegistry

Global registry for all available data sources.
"""
mutable struct DataSourceRegistry
    sources::Dict{String, DataSource}
    source_metadata::Dict{String, Dict}

    function DataSourceRegistry()
        new(Dict(), Dict())
    end
end

const GLOBAL_SOURCE_REGISTRY = DataSourceRegistry()

"""
    register_source(source::DataSource; metadata::Dict=Dict())

Register a data source globally.

# Arguments
- `source::DataSource`: Source to register
- `metadata::Dict`: Additional metadata
"""
function register_source(source::DataSource; metadata::Dict=Dict())
    GLOBAL_SOURCE_REGISTRY.sources[source.name] = source
    GLOBAL_SOURCE_REGISTRY.source_metadata[source.name] = metadata
    @info "Registered source: $(source.name)"
end

"""
    get_source(name::String)

Retrieve a registered source by name.
"""
function get_source(name::String)
    return get(GLOBAL_SOURCE_REGISTRY.sources, name, nothing)
end

"""
    list_sources()

List all registered sources.

# Returns
- `Vector{String}`: List of source names
"""
function list_sources()
    return collect(keys(GLOBAL_SOURCE_REGISTRY.sources))
end

"""
    get_source_info(name::String)

Get detailed information about a source.

# Returns
- `Dict`: Source information
"""
function get_source_info(name::String)
    source = get_source(name)
    if isnothing(source)
        return nothing
    end

    return Dict(
        "name" => source.name,
        "type" => source.source_type,
        "url" => source.url,
        "description" => source.description,
        "enabled" => source.enabled,
        "metadata" => GLOBAL_SOURCE_REGISTRY.source_metadata[name]
    )
end

"""
    list_sources_by_type(source_type::String)

List all sources of a specific type.

# Arguments
- `source_type::String`: Type of source (NOAA, USGS, etc.)

# Returns
- `Vector{String}`: List of matching source names
"""
function list_sources_by_type(source_type::String)
    return [name for (name, source) in GLOBAL_SOURCE_REGISTRY.sources
            if source.source_type == source_type]
end

"""
    enable_source(name::String)

Enable a source.
"""
function enable_source(name::String)
    source = get_source(name)
    if !isnothing(source)
        GLOBAL_SOURCE_REGISTRY.sources[name] = DataSource(
            source.name, source.source_type, source.url,
            source.credentials, source.parameters, source.description, true
        )
        @info "Enabled source: $name"
    end
end

"""
    disable_source(name::String)

Disable a source.
"""
function disable_source(name::String)
    source = get_source(name)
    if !isnothing(source)
        GLOBAL_SOURCE_REGISTRY.sources[name] = DataSource(
            source.name, source.source_type, source.url,
            source.credentials, source.parameters, source.description, false
        )
        @info "Disabled source: $name"
    end
end

"""
    get_sources_by_capability(capability::String)

Get sources by capability (e.g., "weather", "elevation", "land_cover").

# Returns
- `Vector{String}`: List of source names with the capability
"""
function get_sources_by_capability(capability::String)
    matching = String[]
    for (name, source) in GLOBAL_SOURCE_REGISTRY.sources
        metadata = GLOBAL_SOURCE_REGISTRY.source_metadata[name]
        if haskey(metadata, "capabilities") && capability in metadata["capabilities"]
            push!(matching, name)
        end
    end
    return matching
end

"""
    get_source_statistics()

Get statistics about registered sources.

# Returns
- `Dict`: Registry statistics
"""
function get_source_statistics()
    sources = GLOBAL_SOURCE_REGISTRY.sources
    total = length(sources)
    enabled = sum(1 for (_, source) in sources if source.enabled)
    disabled = total - enabled

    types = Set(source.source_type for (_, source) in sources)

    return Dict(
        "total_sources" => total,
        "enabled" => enabled,
        "disabled" => disabled,
        "source_types" => collect(types)
    )
end
