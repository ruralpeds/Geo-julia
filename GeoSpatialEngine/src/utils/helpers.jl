"""
Helper functions and utilities.
"""

function format_bounds(minx::Float64, miny::Float64, maxx::Float64, maxy::Float64)
    return (minx=minx, miny=miny, maxx=maxx, maxy=maxy)
end

function expand_bounds(bounds::NamedTuple, factor::Float64)
    cx = (bounds.minx + bounds.maxx) / 2
    cy = (bounds.miny + bounds.maxy) / 2
    dx = (bounds.maxx - bounds.minx) / 2 * factor
    dy = (bounds.maxy - bounds.miny) / 2 * factor
    return (minx=cx-dx, miny=cy-dy, maxx=cx+dx, maxy=cy+dy)
end

function degrees_to_meters(degrees::Float64, latitude::Float64)
    # Approximate conversion at given latitude
    return degrees * 111320.0 * cos(latitude * π / 180)
end

function distance_haversine(lat1::Float64, lon1::Float64, lat2::Float64, lon2::Float64)
    R = 6371.0  # Earth radius in km
    dlat = (lat2 - lat1) * π / 180
    dlon = (lon2 - lon1) * π / 180
    a = sin(dlat/2)^2 + cos(lat1*π/180) * cos(lat2*π/180) * sin(dlon/2)^2
    c = 2 * atan(sqrt(a), sqrt(1-a))
    return R * c * 1000  # Return in meters
end

function format_timestamp(dt::DateTime)
    return Dates.format(dt, "yyyy-mm-dd HH:MM:SS")
end

function create_progress_bar(current::Int, total::Int)
    pct = (current / total) * 100
    bar_length = 50
    filled = Int(round((current / total) * bar_length))
    bar = "▓" ^ filled * "░" ^ (bar_length - filled)
    return "[$bar] $pct%"
end
