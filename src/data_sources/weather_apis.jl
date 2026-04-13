"""
Weather API Integrations (OpenWeatherMap, ECMWF)
"""

module WeatherAPIsAdapter

function get_openweather_data(api_key::String, lat::Float64, lon::Float64)
    payload = Dict(
        "type" => "WEATHER",
        "provider" => "OpenWeatherMap",
        "latitude" => lat,
        "longitude" => lon,
        "units" => "metric"
    )
    return payload
end

function get_ecmwf_forecast(api_key::String, bounds::Tuple, model::String="IFS")
    payload = Dict(
        "type" => "FORECAST",
        "provider" => "ECMWF",
        "model" => model,
        "bounds" => bounds
    )
    return payload
end

end
