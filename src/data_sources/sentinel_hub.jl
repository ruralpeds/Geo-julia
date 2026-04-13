"""
Sentinel Hub Data Source Integration
"""

module SentinelHubAdapter
using HTTP, JSON3

function get_optical_data(api_key::String, bounds::Tuple, start_date::String, end_date::String)
    payload = Dict(
        "type" => "OPTICAL",
        "collections" => ["SENTINEL2_L2A", "SENTINEL1"],
        "bounds" => bounds,
        "start_date" => start_date,
        "end_date" => end_date
    )
    return payload
end

function get_sar_data(api_key::String, bounds::Tuple, start_date::String, end_date::String)
    payload = Dict(
        "type" => "SAR",
        "collection" => "SENTINEL1_GRD",
        "bounds" => bounds,
        "start_date" => start_date,
        "end_date" => end_date
    )
    return payload
end

end
