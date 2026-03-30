# src/data/routing.jl
# Travel-time computation via OSRM and road network download via Overpass API.

using HTTP, JSON

# ──────────────────────────────────────────────────────────────────────────────
# OSRM travel-time matrix
# ──────────────────────────────────────────────────────────────────────────────

const OSRM_PUBLIC_HOST  = "http://router.project-osrm.org"
const OVERPASS_API_URL  = "https://overpass-api.de/api/interpreter"

"""
    osrm_table(origins, destinations;
               host="http://router.project-osrm.org") -> Matrix{Float64}

Compute an all-pairs driving travel-time matrix via the OSRM Table service.

- `origins`      — `Vector{NTuple{2,Float64}}` of `(lat, lon)` pairs
- `destinations` — `Vector{NTuple{2,Float64}}` of `(lat, lon)` pairs
- `host`         — OSRM backend URL (default: public demo server)

Returns an `n_origins × n_destinations` `Matrix{Float64}` of travel times
in **minutes**.  Unreachable pairs are set to `Inf`.

**Rate limits:** The public OSRM demo server is suitable for small ad-hoc
queries only.  For production analysis, self-host OSRM with Docker:
```
docker run -t -i -p 5000:5000 -v \$(pwd)/data:/data \\
  osrm/osrm-backend osrm-routed --algorithm mld /data/north-america-latest.osrm
```
Then use `host="http://localhost:5000"`.
"""
function osrm_table(origins::Vector{NTuple{2,Float64}},
                     destinations::Vector{NTuple{2,Float64}};
                     host::AbstractString = OSRM_PUBLIC_HOST)::Matrix{Float64}
    all_locs  = vcat(origins, destinations)
    n_orig    = length(origins)
    n_dest    = length(destinations)

    coord_str = join(["$(lon),$(lat)" for (lat, lon) in all_locs], ";")
    src_str   = join(0:(n_orig - 1), ";")
    dst_str   = join(n_orig:(length(all_locs) - 1), ";")

    url = "$(host)/table/v1/driving/$(coord_str)" *
          "?sources=$(src_str)&destinations=$(dst_str)&annotations=duration"

    resp = try
        HTTP.get(url; readtimeout = 120, status_exception = true)
    catch e
        error("OSRM request failed.\nURL: $url\nError: $(e)")
    end

    data = JSON.parse(String(resp.body))
    data["code"] == "Ok" ||
        error("OSRM error: $(data["code"]) — $(get(data, "message", "unknown"))")

    mat = Matrix{Float64}(undef, n_orig, n_dest)
    for i in 1:n_orig, j in 1:n_dest
        t = data["durations"][i][j]
        mat[i, j] = isnothing(t) ? Inf : t / 60.0   # seconds → minutes
    end

    return mat
end

"""
    osrm_route(origin, destination;
               host="http://router.project-osrm.org") -> NamedTuple

Compute a single driving route between two points.

Returns `(duration_min, distance_km, geometry_geojson)`.
"""
function osrm_route(origin::NTuple{2,Float64},
                     destination::NTuple{2,Float64};
                     host::AbstractString = OSRM_PUBLIC_HOST)
    lat1, lon1 = origin
    lat2, lon2 = destination
    url = "$(host)/route/v1/driving/$(lon1),$(lat1);$(lon2),$(lat2)" *
          "?overview=simplified&geometries=geojson"

    resp = HTTP.get(url; readtimeout = 30, status_exception = true)
    data = JSON.parse(String(resp.body))
    data["code"] == "Ok" ||
        error("OSRM route error: $(data["code"])")

    route = data["routes"][1]
    (duration_min   = route["duration"] / 60.0,
     distance_km    = route["distance"] / 1000.0,
     geometry_geojson = route["geometry"])
end

# ──────────────────────────────────────────────────────────────────────────────
# OpenStreetMap road network download via Overpass API
# ──────────────────────────────────────────────────────────────────────────────

"""
    download_osm_network(bbox; transport="drive",
                          outfile=nothing) -> String

Download an OpenStreetMap road network for a bounding box from the
Overpass API and return the raw OSM XML string.

- `bbox`      — `(south, west, north, east)` in WGS84 decimal degrees
- `transport` — `"drive"` (paved roads), `"walk"` (all paths), `"all"`
- `outfile`   — if provided, write OSM XML to this path (for OpenStreetMapX.jl)

The returned XML can be saved as a `.osm` file and loaded with
`OpenStreetMapX.get_map_data(outfile)`.
"""
function download_osm_network(bbox::NTuple{4,Float64};
                               transport::AbstractString = "drive",
                               outfile::Union{Nothing, AbstractString} = nothing)::String
    s, w, n, e = bbox

    filter_str = if transport == "drive"
        "[\"highway\"~\"motorway|trunk|primary|secondary|tertiary|residential|unclassified\"]"
    elseif transport == "walk"
        "[\"highway\"][\"highway\"!~\"motorway|trunk\"]"
    else
        "[\"highway\"]"
    end

    query = """
    [out:xml][timeout:300];
    (
      way$(filter_str)($(s),$(w),$(n),$(e));
      >;
    );
    out body;
    """

    @info "Downloading OSM road network for bbox $(bbox) via Overpass API…"
    resp = try
        HTTP.post(OVERPASS_API_URL,
            ["Content-Type" => "application/x-www-form-urlencoded"],
            "data=" * HTTP.URIs.escapeuri(query);
            readtimeout = 300, status_exception = true)
    catch e
        error("Overpass API request failed.\nError: $(e)")
    end

    xml = String(resp.body)

    if !isnothing(outfile)
        write(outfile, xml)
        @info "OSM network saved to $outfile"
    end

    return xml
end
