"""
Generic data source handler for user-defined sources.
"""

function create_custom_source(name::String, url::String; 
                             source_type::String="GENERIC",
                             description::String="")
    source = DataSource(
        name, source_type, url, Dict(), Dict(), description, true
    )
    return source
end

function _ingest_from_custom_api(url::String, params::Dict)
    @info "Ingesting from custom API: $url"
    
    df = DataFrame()
    metadata = Dict("source" => "Custom_API", "url" => url, "params" => params)
    return GeoSpatialData(df; metadata=metadata, crs="EPSG:4326")
end
