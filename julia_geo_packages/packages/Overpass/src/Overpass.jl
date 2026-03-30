"""
    Overpass.jl

Julia client for the OpenStreetMap Overpass API.
Fluent query builder, healthcare POI download, road network download.
Fills the Julia ecosystem gap: no OSMnx equivalent exists.

Vol 3 — Julia Package Engineering, Chapter 22.5
"""
module Overpass

using HTTP
using JSON3
using DataFrames
using SHA
using Dates

# ── Type exports ─────────────────────────────────────────────────────────────
export OverpassQuery, OsmData

# ── Function exports ──────────────────────────────────────────────────────────
export within_bbox, node_with_tag, way_with_tag, relation_with_tag
export recurse_down, output, build_query
export run_query, download_healthcare_pois, download_road_network
export nodes_to_df, ways_to_df, pois_to_df

# ── Constants ─────────────────────────────────────────────────────────────────
const OVERPASS_PUBLIC_URL = "https://overpass-api.de/api/interpreter"
const CACHE_DIR           = joinpath(homedir(), ".julia_geodata", "overpass_cache")
const CACHE_TTL_HOURS     = 24
const RATE_LIMIT_SEC      = 1.0   # min seconds between requests

# Healthcare-relevant OSM tags
const HEALTHCARE_TAGS = [
    ("amenity", "hospital"),
    ("amenity", "clinic"),
    ("amenity", "pharmacy"),
    ("amenity", "doctors"),
    ("amenity", "dentist"),
    ("amenity", "nursing_home"),
    ("healthcare", "*"),
    ("amenity", "social_facility"),
]

# ── Types ─────────────────────────────────────────────────────────────────────

"""
    OsmData

Container for parsed OSM data from Overpass API.

# Fields
- `nodes`     : Dict{Int64, NamedTuple(lat, lon, tags)}
- `ways`      : Dict{Int64, NamedTuple(nodes, tags)}
- `relations` : Dict{Int64, NamedTuple(members, tags)}
- `metadata`  : NamedTuple(query_time, api_version, note)
"""
struct OsmData
    nodes     :: Dict{Int64, @NamedTuple{lat::Float64, lon::Float64, tags::Dict{String,String}}}
    ways      :: Dict{Int64, @NamedTuple{nodes::Vector{Int64}, tags::Dict{String,String}}}
    relations :: Dict{Int64, @NamedTuple{members::Vector{Dict}, tags::Dict{String,String}}}
    metadata  :: @NamedTuple{query_time::String, api_version::String, note::String}
end

function Base.show(io::IO, d::OsmData)
    println(io, "OsmData(nodes=$(length(d.nodes)), ways=$(length(d.ways)), relations=$(length(d.relations)))")
    println(io, "  queried at: $(d.metadata.query_time)")
end

"""
    OverpassQuery

Fluent builder for Overpass QL queries.

Build queries using pipe syntax:
```julia
q = OverpassQuery() |>
    within_bbox(45.0, -100.0, 47.0, -96.0) |>
    node_with_tag("amenity", "hospital") |>
    recurse_down() |>
    output(:json)
```
"""
mutable struct OverpassQuery
    bbox       :: Union{Nothing, Tuple{Float64,Float64,Float64,Float64}}
    filters    :: Vector{String}  # QL filter statements
    out_mode   :: Symbol          # :json, :xml, :csv
    recurse    :: Bool
    timeout    :: Int             # Overpass timeout in seconds
    max_size   :: Int             # max response bytes
    host       :: String

    function OverpassQuery(;
        host    = OVERPASS_PUBLIC_URL,
        timeout = 180,
        max_size = 536870912,  # 512 MB
    )
        new(nothing, String[], :json, false, timeout, max_size, host)
    end
end

# ── Fluent builder methods ───────────────────────────────────────────────────

"""
    within_bbox(q, south, west, north, east) -> OverpassQuery

Restrict query to a bounding box (decimal degrees, WGS84).
"""
function within_bbox(q::OverpassQuery, south::Real, west::Real, north::Real, east::Real)
    q.bbox = (Float64(south), Float64(west), Float64(north), Float64(east))
    q
end

# Pipe-friendly: within_bbox(s,w,n,e) returns a function
function within_bbox(south::Real, west::Real, north::Real, east::Real)
    q -> within_bbox(q, south, west, north, east)
end

"""
    node_with_tag(q, key, value="*") -> OverpassQuery

Add a node filter for key=value. Use "*" for any value.
"""
function node_with_tag(q::OverpassQuery, key::String, value::String = "*")
    bbox_str = _bbox_str(q.bbox)
    tag_str  = value == "*" ? "[\"$(key)\"]" : "[\"$(key)\"=\"$(value)\"]"
    push!(q.filters, "node$(tag_str)$(bbox_str)")
    q
end
node_with_tag(key::String, value::String = "*") = q -> node_with_tag(q, key, value)

"""
    way_with_tag(q, key, value="*") -> OverpassQuery

Add a way filter for key=value.
"""
function way_with_tag(q::OverpassQuery, key::String, value::String = "*")
    bbox_str = _bbox_str(q.bbox)
    tag_str  = value == "*" ? "[\"$(key)\"]" : "[\"$(key)\"=\"$(value)\"]"
    push!(q.filters, "way$(tag_str)$(bbox_str)")
    q
end
way_with_tag(key::String, value::String = "*") = q -> way_with_tag(q, key, value)

"""
    relation_with_tag(q, key, value="*") -> OverpassQuery

Add a relation filter.
"""
function relation_with_tag(q::OverpassQuery, key::String, value::String = "*")
    bbox_str = _bbox_str(q.bbox)
    tag_str  = value == "*" ? "[\"$(key)\"]" : "[\"$(key)\"=\"$(value)\"]"
    push!(q.filters, "relation$(tag_str)$(bbox_str)")
    q
end
relation_with_tag(key::String, value::String = "*") = q -> relation_with_tag(q, key, value)

"""
    recurse_down(q) -> OverpassQuery

Add `(._;>;)` to resolve way node references and relation members.
"""
function recurse_down(q::OverpassQuery)
    q.recurse = true
    q
end
recurse_down() = q -> recurse_down(q)

"""
    output(q, mode=:json) -> OverpassQuery

Set output format: `:json`, `:xml`, or `:csv`.
"""
function output(q::OverpassQuery, mode::Symbol = :json)
    q.out_mode = mode
    q
end
output(mode::Symbol = :json) = q -> output(q, mode)

# ── Build Overpass QL string ──────────────────────────────────────────────────

"""
    build_query(q) -> String

Build the Overpass QL query string from the fluent builder state.
"""
function build_query(q::OverpassQuery)::String
    out_fmt = q.out_mode == :json ? "json" : q.out_mode == :xml ? "xml" : "csv"
    header  = "[out:$(out_fmt)][timeout:$(q.timeout)][maxsize:$(q.max_size)];"
    body    = join(q.filters, "\n  ")
    union   = "(\n  $(body)\n);"
    recurse = q.recurse ? "(._;>.);\n" : ""
    "$(header)\n$(union)\n$(recurse)out body;"
end

function Base.show(io::IO, q::OverpassQuery)
    println(io, "OverpassQuery:")
    println(io, "  bbox: $(q.bbox)")
    println(io, "  filters: $(length(q.filters))")
    println(io, "  output: $(q.out_mode)")
    println(io, build_query(q))
end

# ── run_query ─────────────────────────────────────────────────────────────────

# Global rate-limit tracker
const _LAST_REQUEST_TIME = Ref(0.0)

"""
    run_query(q; use_cache=true) -> OsmData

Execute an Overpass query. Results are cached to disk for 24 hours.
Rate-limited to 1 request/second (Overpass API requirement).

# Arguments
- `q`          : `OverpassQuery` built with fluent API
- `use_cache`  : cache results to `~/.julia_geodata/overpass_cache/` (default true)
"""
function run_query(q::OverpassQuery; use_cache::Bool = true)::OsmData
    ql_str = build_query(q)

    # Cache key = SHA256 of query string
    if use_cache
        mkpath(CACHE_DIR)
        key      = bytes2hex(sha256(ql_str))
        cache_path = joinpath(CACHE_DIR, "$(key).json")
        if isfile(cache_path)
            age_hours = (time() - mtime(cache_path)) / 3600
            if age_hours < CACHE_TTL_HOURS
                @info "Overpass: loading from cache ($(round(age_hours; digits=1))h old)"
                return _parse_overpass_json(read(cache_path, String))
            end
        end
    end

    # Rate limiting
    elapsed = time() - _LAST_REQUEST_TIME[]
    if elapsed < RATE_LIMIT_SEC
        sleep(RATE_LIMIT_SEC - elapsed)
    end

    @info "Overpass: executing query ($(length(ql_str)) chars)"
    resp = try
        HTTP.post(
            q.host;
            body    = "data=$(HTTP.escapeuri(ql_str))",
            headers = ["Content-Type" => "application/x-www-form-urlencoded"],
            connect_timeout = 30,
            readtimeout = q.timeout + 30,
        )
    catch e
        error("Overpass API request failed: $e\nQuery:\n$(ql_str)")
    end
    _LAST_REQUEST_TIME[] = time()

    body_str = String(resp.body)

    if use_cache
        write(cache_path, body_str)
    end

    _parse_overpass_json(body_str)
end

function _parse_overpass_json(json_str::String)::OsmData
    data = JSON3.read(json_str)
    meta = get(data, :osm3s, Dict())

    nodes     = Dict{Int64, @NamedTuple{lat::Float64, lon::Float64, tags::Dict{String,String}}}()
    ways      = Dict{Int64, @NamedTuple{nodes::Vector{Int64}, tags::Dict{String,String}}}()
    relations = Dict{Int64, @NamedTuple{members::Vector{Dict}, tags::Dict{String,String}}}()

    for el in get(data, :elements, [])
        typ = get(el, :type, "")
        id  = Int64(get(el, :id, 0))
        raw_tags = get(el, :tags, Dict())
        tags = Dict{String,String}(string(k) => string(v) for (k, v) in raw_tags)

        if typ == "node"
            lat = Float64(get(el, :lat, 0.0))
            lon = Float64(get(el, :lon, 0.0))
            nodes[id] = (lat=lat, lon=lon, tags=tags)
        elseif typ == "way"
            nd_ids = Int64[Int64(n) for n in get(el, :nodes, [])]
            ways[id] = (nodes=nd_ids, tags=tags)
        elseif typ == "relation"
            members = [Dict(string(k) => string(v) for (k, v) in m) for m in get(el, :members, [])]
            relations[id] = (members=members, tags=tags)
        end
    end

    metadata = (
        query_time  = string(get(meta, :timestamp_osm_base, now())),
        api_version = string(get(meta, :copyright, "OpenStreetMap contributors")),
        note        = string(get(meta, :note, "")),
    )

    OsmData(nodes, ways, relations, metadata)
end

# ── DataFrames converters ─────────────────────────────────────────────────────

"""
    nodes_to_df(data::OsmData; tag_keys) -> DataFrame

Convert OsmData nodes to a DataFrame with id, lat, lon, and selected tag columns.
"""
function nodes_to_df(data::OsmData;
                      tag_keys::Vector{String} = String[])::DataFrame
    ids  = collect(keys(data.nodes))
    isempty(ids) && return DataFrame()

    df = DataFrame(
        id  = ids,
        lat = [data.nodes[i].lat for i in ids],
        lon = [data.nodes[i].lon for i in ids],
    )

    for k in tag_keys
        df[!, k] = [get(data.nodes[i].tags, k, missing) for i in ids]
    end

    # Add all tags as a JSON string column if no specific keys given
    if isempty(tag_keys)
        df.tags = [string(data.nodes[i].tags) for i in ids]
    end

    df
end

"""
    ways_to_df(data::OsmData; tag_keys) -> DataFrame

Convert OsmData ways to a DataFrame.
"""
function ways_to_df(data::OsmData;
                     tag_keys::Vector{String} = String[])::DataFrame
    ids = collect(keys(data.ways))
    isempty(ids) && return DataFrame()

    df = DataFrame(
        id       = ids,
        n_nodes  = [length(data.ways[i].nodes) for i in ids],
    )

    for k in tag_keys
        df[!, k] = [get(data.ways[i].tags, k, missing) for i in ids]
    end

    if isempty(tag_keys)
        df.tags = [string(data.ways[i].tags) for i in ids]
    end

    df
end

# ── download_healthcare_pois ───────────────────────────────────────────────────

"""
    download_healthcare_pois(bbox; host=OVERPASS_PUBLIC_URL, use_cache=true) -> DataFrame

Download healthcare points of interest from OpenStreetMap for a bounding box.

Returns a DataFrame with: id, lat, lon, name, amenity, healthcare, address, phone,
operator, and other healthcare-relevant tags.

# Arguments
- `bbox` : (south, west, north, east) decimal degrees
"""
function download_healthcare_pois(bbox::Tuple{Real,Real,Real,Real};
                                   host      :: String = OVERPASS_PUBLIC_URL,
                                   use_cache :: Bool   = true)::DataFrame
    s, w, n, e = Float64.(bbox)

    q = OverpassQuery(; host)
    q.bbox = (s, w, n, e)
    q.timeout = 180

    # Add all healthcare-relevant tag filters
    for (key, val) in HEALTHCARE_TAGS
        node_with_tag(q, key, val)
        way_with_tag(q, key, val)
    end
    recurse_down(q)
    output(q, :json)

    data = run_query(q; use_cache)

    pois_to_df(data)
end

"""
    pois_to_df(data::OsmData) -> DataFrame

Convert OsmData to a healthcare POI DataFrame, extracting common fields.
"""
function pois_to_df(data::OsmData)::DataFrame
    rows = []

    for (id, node) in data.nodes
        tags = node.tags
        # Only include nodes with healthcare-relevant tags
        is_healthcare = haskey(tags, "amenity") && tags["amenity"] ∈
            ["hospital","clinic","pharmacy","doctors","dentist","nursing_home","social_facility"] ||
            haskey(tags, "healthcare")
        is_healthcare || continue

        push!(rows, (
            id          = id,
            lat         = node.lat,
            lon         = node.lon,
            name        = get(tags, "name", missing),
            amenity     = get(tags, "amenity", missing),
            healthcare  = get(tags, "healthcare", missing),
            addr_street = get(tags, "addr:street", missing),
            addr_city   = get(tags, "addr:city", missing),
            addr_state  = get(tags, "addr:state", missing),
            phone       = get(tags, "phone", get(tags, "contact:phone", missing)),
            operator    = get(tags, "operator", missing),
            beds        = get(tags, "beds", missing),
            emergency   = get(tags, "emergency", missing),
            osm_type    = "node",
        ))
    end

    isempty(rows) ? DataFrame() : DataFrame(rows)
end

# ── download_road_network ─────────────────────────────────────────────────────

"""
    download_road_network(bbox; transport="drive", outfile=nothing, host=..., use_cache=true) -> String

Download OpenStreetMap road network from Overpass API as JSON.

# Arguments
- `bbox`      : (south, west, north, east) decimal degrees
- `transport` : "drive" (motorable roads), "walk" (all paths), "all"
- `outfile`   : save path; if nothing, saves to cache directory
- `use_cache` : use disk cache (default true)

Returns path to the saved file.
"""
function download_road_network(bbox::Tuple{Real,Real,Real,Real};
                                transport :: String = "drive",
                                outfile   :: Union{String, Nothing} = nothing,
                                host      :: String = OVERPASS_PUBLIC_URL,
                                use_cache :: Bool   = true)::String
    s, w, n, e = Float64.(bbox)
    bbox_str = "($(s),$(w),$(n),$(e))"

    # Highway filters per transport mode
    highway_filters = if transport == "drive"
        ["motorway", "trunk", "primary", "secondary", "tertiary",
         "unclassified", "residential", "motorway_link", "trunk_link",
         "primary_link", "secondary_link", "tertiary_link"]
    elseif transport == "walk"
        ["footway", "path", "pedestrian", "steps", "track",
         "residential", "unclassified", "primary", "secondary", "tertiary"]
    else  # "all"
        ["motorway","trunk","primary","secondary","tertiary",
         "unclassified","residential","footway","path","track","service"]
    end

    filter_lines = join(
        ["  way[\"highway\"=\"$(hw)\"]$(bbox_str);" for hw in highway_filters],
        "\n"
    )

    ql = """
[out:json][timeout:300][maxsize:536870912];
(
$(filter_lines)
);
(._;>;);
out body;
"""

    # Cache by hash of query
    key        = bytes2hex(sha256(ql))
    cache_path = joinpath(CACHE_DIR, "road_$(key).json")
    out_path   = outfile === nothing ? cache_path : outfile

    mkpath(dirname(out_path))

    if use_cache && isfile(cache_path) && (time() - mtime(cache_path)) / 3600 < CACHE_TTL_HOURS
        @info "Road network: loading from cache"
        use_cache && outfile !== nothing && cp(cache_path, outfile; force=true)
        return out_path
    end

    elapsed = time() - _LAST_REQUEST_TIME[]
    elapsed < RATE_LIMIT_SEC && sleep(RATE_LIMIT_SEC - elapsed)

    @info "Downloading road network for bbox=$(bbox), transport=$(transport)"
    resp = try
        HTTP.post(
            host;
            body    = "data=$(HTTP.escapeuri(ql))",
            headers = ["Content-Type" => "application/x-www-form-urlencoded"],
            connect_timeout = 30,
            readtimeout     = 330,
        )
    catch e
        error("Overpass road network download failed: $e")
    end
    _LAST_REQUEST_TIME[] = time()

    write(out_path, resp.body)
    @info "Road network saved to: $(out_path) ($(round(filesize(out_path)/1024^2; digits=1)) MB)"
    out_path
end

# ── Helpers ───────────────────────────────────────────────────────────────────

function _bbox_str(bbox::Nothing)
    ""
end
function _bbox_str(bbox::Tuple{Float64,Float64,Float64,Float64})
    s, w, n, e = bbox
    "($(s),$(w),$(n),$(e))"
end

end # module Overpass
