"""
Google Earth Engine Data Source Integration
"""

module GoogleEarthEngineAdapter
using HTTP, JSON3

const GEE_BASE_URL = "https://earthengine.googleapis.com"

function get_sentinel2_data(api_key::String, bounds::Tuple, start_date::String, end_date::String)
    payload = Dict(
        "type" => "IMAGE_COLLECTION",
        "collection" => "COPERNICUS/S2_SR",
        "bounds" => bounds,
        "start_date" => start_date,
        "end_date" => end_date
    )
    return payload
end

function get_landsat8_data(api_key::String, bounds::Tuple, start_date::String, end_date::String)
    payload = Dict(
        "type" => "IMAGE_COLLECTION",
        "collection" => "LANDSAT/LC08/C02/T1",
        "bounds" => bounds,
        "start_date" => start_date,
        "end_date" => end_date
    )
    return payload
end

function get_modis_data(api_key::String, bounds::Tuple, start_date::String, end_date::String)
    payload = Dict(
        "type" => "IMAGE_COLLECTION",
        "collection" => "MODIS/006/MOD13Q1",
        "bounds" => bounds,
        "start_date" => start_date,
        "end_date" => end_date
    )
    return payload
end

end
