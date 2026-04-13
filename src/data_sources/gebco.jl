"""
GEBCO Bathymetry Data Integration
"""

module GEBCOAdapter

function get_bathymetry_data(bounds::Tuple, resolution::Float64=0.5)
    payload = Dict(
        "type" => "BATHYMETRY",
        "dataset" => "GEBCO_2023",
        "bounds" => bounds,
        "resolution" => resolution,
        "units" => "meters"
    )
    return payload
end

end
