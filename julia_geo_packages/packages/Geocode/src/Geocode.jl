"""
    Geocode.jl

The first geocoding library for Julia.
Fills the critical ecosystem gap: Julia has zero native geocoding packages.

Provides multiple backends:
- Census Bureau Geocoder (U.S. addresses, free, no API key)
- Nominatim/OpenStreetMap (global, free, requires User-Agent, 1s rate limit)
- ArcGIS World Geocoding Service (global, free tier, no key required)

Vol 3 — Julia Package Engineering, Chapter 22.3
"""
module Geocode

using HTTP
using JSON3
using CSV
using DataFrames

# ── Type exports ─────────────────────────────────────────────────────────────
export GeocodedAddress, GeocoderBackend
export CensusGeocoder, NominatimGeocoder, ArcGISGeocoder

# ── Function exports ──────────────────────────────────────────────────────────
export geocode, geocode_batch, geocode_all
export normalize_address, is_po_box, is_rural_route, standardize_state

# ── Constants ─────────────────────────────────────────────────────────────────
const CENSUS_GEOCODER_URL = "https://geocoding.geo.census.gov/geocoder/locations/addressbatch"
const NOMINATIM_URL       = "https://nominatim.openstreetmap.org/search"
const ARCGIS_URL          = "https://geocode.arcgis.com/arcgis/rest/services/World/GeocodeServer/findAddressCandidates"
const PACKAGE_VERSION     = "0.1.0"

# ── Types ─────────────────────────────────────────────────────────────────────

"""Abstract geocoder backend type."""
abstract type GeocoderBackend end

"""
    GeocodedAddress

Geocoding result for a single address.

# Fields
- `id`              : original row identifier
- `input_address`   : original address string
- `matched_address` : address as matched by geocoder (may differ)
- `lat`             : latitude (NaN if no match)
- `lon`             : longitude (NaN if no match)
- `match_type`      : "Exact", "Non_Exact", "Tie", "No_Match", etc.
- `tract_fips`      : 11-digit census tract FIPS (Census geocoder only)
- `score`           : confidence score 0–100 (ArcGIS/Nominatim)
- `backend`         : geocoder used (`:census`, `:nominatim`, `:arcgis`)
"""
struct GeocodedAddress
    id              :: String
    input_address   :: String
    matched_address :: String
    lat             :: Float64
    lon             :: Float64
    match_type      :: String
    tract_fips      :: String
    score           :: Float64
    backend         :: Symbol
end

function Base.show(io::IO, g::GeocodedAddress)
    matched = isnan(g.lat) ? "NO MATCH" : "$(round(g.lat;digits=5)), $(round(g.lon;digits=5))"
    println(io, "GeocodedAddress($(g.id)): $(g.input_address)")
    println(io, "  → $(matched) [$(g.match_type), $(g.backend)]")
end

# ── Census Geocoder ───────────────────────────────────────────────────────────

"""
    CensusGeocoder

U.S.-only geocoder using the Census Bureau Geocoding Services API.
- No API key required
- Max 1,000 addresses per batch
- Returns census tract FIPS codes
- Free and operated by U.S. Census Bureau
"""
struct CensusGeocoder <: GeocoderBackend
    vintage :: String
    CensusGeocoder(; vintage="Current") = new(vintage)
end

"""
    geocode_batch(backend::CensusGeocoder, addresses::DataFrame) -> DataFrame

Batch geocode up to 1,000 U.S. addresses via Census Bureau Geocoder.

`addresses` must have columns: `id`, `street`, `city`, `state`, `zip`

Returns input columns plus: `lat`, `lon`, `match_type`, `matched_address`, `tract_fips`
"""
function geocode_batch(backend::CensusGeocoder, addresses::DataFrame)::DataFrame
    nrow(addresses) > 1000 && error("Census geocoder max batch is 1,000. Use geocode_all().")

    required = ["id", "street", "city", "state", "zip"]
    for col in required
        col ∉ names(addresses) && error("Missing column: $col")
    end

    # Build CSV payload
    csv_content = join(
        ["$(row.id),\"$(normalize_address(row.street))\",\"$(row.city)\",$(row.state),$(row.zip)"
         for row in eachrow(addresses)],
        "\n"
    )

    body = "\"addressFile\"" * "\r\n" *
           "Content-Disposition: form-data; name=\"addressFile\"; filename=\"addresses.csv\"\r\n" *
           "Content-Type: text/plain\r\n\r\n" *
           csv_content * "\r\n"

    boundary = "----GeoJuliaBoundary$(rand(UInt32))"
    resp = try
        HTTP.post(
            CENSUS_GEOCODER_URL;
            query = Dict("benchmark" => "Public_AR_$(backend.vintage)", "vintage" => backend.vintage),
            headers = ["Content-Type" => "multipart/form-data; boundary=$(boundary)"],
            body = "--$(boundary)\r\n" *
                   "Content-Disposition: form-data; name=\"addressFile\"; filename=\"batch.csv\"\r\n" *
                   "Content-Type: application/octet-stream\r\n\r\n" *
                   csv_content * "\r\n" *
                   "--$(boundary)\r\n" *
                   "Content-Disposition: form-data; name=\"benchmark\"\r\n\r\n" *
                   "Public_AR_$(backend.vintage)\r\n" *
                   "--$(boundary)--\r\n",
            connect_timeout = 30,
            readtimeout = 120,
        )
    catch e
        @warn "Census geocoder HTTP error: $e"
        return _empty_geocode_result(addresses)
    end

    _parse_census_response(String(resp.body), addresses)
end

function _parse_census_response(body::String, input::DataFrame)::DataFrame
    lines = filter(!isempty, split(strip(body), "\n"))
    results = DataFrame(
        id              = String[],
        input_address   = String[],
        matched_address = String[],
        lat             = Float64[],
        lon             = Float64[],
        match_type      = String[],
        tract_fips      = String[],
    )

    for line in lines
        parts = split(line, ",")
        length(parts) < 2 && continue
        id_str     = strip(parts[1], ['"', ' '])
        match_type = length(parts) >= 3 ? strip(parts[3], ['"', ' ']) : "No_Match"

        if match_type == "Match" && length(parts) >= 9
            matched_addr = strip(parts[4], ['"', ' '])
            lon_str      = strip(parts[6], ['"', ' '])
            lat_str      = strip(parts[7], ['"', ' '])
            tract        = length(parts) >= 9 ? strip(parts[9], ['"', ' ']) : ""
            lat = tryparse(Float64, lat_str)
            lon = tryparse(Float64, lon_str)
            push!(results, (id_str, "", matched_addr,
                            lat === nothing ? NaN : lat,
                            lon === nothing ? NaN : lon,
                            match_type, tract))
        else
            push!(results, (id_str, "", "", NaN, NaN, "No_Match", ""))
        end
    end

    # Join back to input to preserve original order
    input_map = Dict(string(row.id) => string(row.street)*", "*string(row.city)*", "*string(row.state) for row in eachrow(input))
    results.input_address = [get(input_map, r.id, "") for r in eachrow(results)]
    results
end

function _empty_geocode_result(addresses::DataFrame)::DataFrame
    DataFrame(
        id              = string.(addresses.id),
        input_address   = string.(addresses.street) .* ", " .* string.(addresses.city),
        matched_address = fill("", nrow(addresses)),
        lat             = fill(NaN, nrow(addresses)),
        lon             = fill(NaN, nrow(addresses)),
        match_type      = fill("Error", nrow(addresses)),
        tract_fips      = fill("", nrow(addresses)),
    )
end

# ── Nominatim Geocoder ────────────────────────────────────────────────────────

"""
    NominatimGeocoder

Global geocoder using OpenStreetMap/Nominatim.
- No API key required
- User-Agent header is REQUIRED by Nominatim usage policy
- Rate limit: maximum 1 request/second
- For production use, self-host Nominatim or use a commercial provider
"""
struct NominatimGeocoder <: GeocoderBackend
    user_agent  :: String
    sleep_sec   :: Float64
    base_url    :: String

    function NominatimGeocoder(;
        user_agent :: String  = "GeoJulia/$(PACKAGE_VERSION) (healthcare-geo-analysis)",
        sleep_sec  :: Float64 = 1.1,
        base_url   :: String  = NOMINATIM_URL,
    )
        isempty(user_agent) && error("Nominatim requires a non-empty User-Agent string")
        new(user_agent, sleep_sec, base_url)
    end
end

"""
    geocode(backend::NominatimGeocoder, address::String; id="1") -> GeocodedAddress

Geocode a single free-text address via Nominatim.
"""
function geocode(backend::NominatimGeocoder, address::String; id::String = "1")::GeocodedAddress
    resp = try
        HTTP.get(
            backend.base_url;
            query = Dict("q" => address, "format" => "json", "limit" => "1"),
            headers = ["User-Agent" => backend.user_agent,
                       "Accept-Language" => "en"],
            connect_timeout = 15,
            readtimeout = 30,
        )
    catch e
        @warn "Nominatim request failed: $e"
        return GeocodedAddress(id, address, "", NaN, NaN, "Error", "", 0.0, :nominatim)
    end

    data = JSON3.read(resp.body)
    if isempty(data)
        return GeocodedAddress(id, address, "", NaN, NaN, "No_Match", "", 0.0, :nominatim)
    end
    first_hit = data[1]
    lat = parse(Float64, get(first_hit, :lat, "NaN"))
    lon = parse(Float64, get(first_hit, :lon, "NaN"))
    display_name = get(first_hit, :display_name, "")
    GeocodedAddress(id, address, display_name, lat, lon, "Match", "", 100.0, :nominatim)
end

"""
    geocode_batch(backend::NominatimGeocoder, addresses::DataFrame) -> DataFrame

Geocode multiple addresses via Nominatim with 1-request-per-second rate limiting.
`addresses` must have: `id`, and either `address` or `street`+`city`+`state`.
"""
function geocode_batch(backend::NominatimGeocoder, addresses::DataFrame)::DataFrame
    has_address_col = "address" ∈ names(addresses)
    results = GeocodedAddress[]

    for (i, row) in enumerate(eachrow(addresses))
        addr_str = if has_address_col
            string(row.address)
        else
            "$(row.street), $(row.city), $(row.state)"
        end
        result = geocode(backend, addr_str; id=string(row.id))
        push!(results, result)
        i < nrow(addresses) && sleep(backend.sleep_sec)
        i % 10 == 0 && @info "Nominatim progress: $i / $(nrow(addresses))"
    end

    _geocoded_to_df(results)
end

# ── ArcGIS Geocoder ───────────────────────────────────────────────────────────

"""
    ArcGISGeocoder

Global geocoder using Esri ArcGIS World Geocoding Service.
- No API key required for public/free tier (limited requests)
- Supports global addresses
- Returns match score 0–100
"""
struct ArcGISGeocoder <: GeocoderBackend
    token :: String  # "" for anonymous
    ArcGISGeocoder(; token::String = "") = new(token)
end

"""
    geocode(backend::ArcGISGeocoder, address::String; id="1") -> GeocodedAddress

Geocode a single address via ArcGIS World Geocoding Service.
"""
function geocode(backend::ArcGISGeocoder, address::String; id::String = "1")::GeocodedAddress
    params = Dict(
        "SingleLine" => address,
        "f"          => "json",
        "outFields"  => "Match_addr,Score",
        "maxLocations" => "1",
    )
    !isempty(backend.token) && (params["token"] = backend.token)

    resp = try
        HTTP.get(ARCGIS_URL; query = params, connect_timeout=15, readtimeout=30)
    catch e
        @warn "ArcGIS request failed: $e"
        return GeocodedAddress(id, address, "", NaN, NaN, "Error", "", 0.0, :arcgis)
    end

    data = JSON3.read(resp.body)
    candidates = get(data, :candidates, [])
    if isempty(candidates)
        return GeocodedAddress(id, address, "", NaN, NaN, "No_Match", "", 0.0, :arcgis)
    end

    best = candidates[1]
    loc  = get(best, :location, Dict())
    lon  = Float64(get(loc, :x, NaN))
    lat  = Float64(get(loc, :y, NaN))
    addr = string(get(best, :address, ""))
    score = Float64(get(best, :score, 0.0))
    GeocodedAddress(id, address, addr, lat, lon, "Match", "", score, :arcgis)
end

"""
    geocode_batch(backend::ArcGISGeocoder, addresses::DataFrame) -> DataFrame

Geocode multiple addresses sequentially via ArcGIS.
"""
function geocode_batch(backend::ArcGISGeocoder, addresses::DataFrame)::DataFrame
    has_address_col = "address" ∈ names(addresses)
    results = GeocodedAddress[]

    for (i, row) in enumerate(eachrow(addresses))
        addr_str = has_address_col ? string(row.address) :
                   "$(row.street), $(row.city), $(row.state) $(row.zip)"
        push!(results, geocode(backend, addr_str; id=string(row.id)))
        i % 50 == 0 && @info "ArcGIS progress: $i / $(nrow(addresses))"
    end

    _geocoded_to_df(results)
end

# ── geocode_all (chunked batch with retry) ────────────────────────────────────

"""
    geocode_all(addresses; backend=CensusGeocoder(), batch_size=500, sleep_sec=1.5, max_retries=2) -> DataFrame

Chunk-and-batch geocoder for large address lists.
Respects rate limits, retries failed batches, logs progress.

# Arguments
- `addresses`  : DataFrame with id, street/city/state/zip or address column
- `backend`    : geocoder backend (default: CensusGeocoder)
- `batch_size` : addresses per batch (default 500; Census max is 1000)
- `sleep_sec`  : sleep between batches (default 1.5 s)
- `max_retries`: retry failed batches this many times
"""
function geocode_all(addresses::DataFrame;
                     backend    :: GeocoderBackend = CensusGeocoder(),
                     batch_size :: Int    = 500,
                     sleep_sec  :: Float64 = 1.5,
                     max_retries:: Int    = 2)::DataFrame

    n       = nrow(addresses)
    batches = Iterators.partition(1:n, batch_size)
    results = DataFrame[]

    for (batch_num, idx) in enumerate(batches)
        batch = addresses[collect(idx), :]
        @info "Geocoding batch $(batch_num)/$(ceil(Int, n/batch_size)) ($(length(idx)) addresses)"

        result = nothing
        for attempt in 1:(max_retries + 1)
            try
                result = geocode_batch(backend, batch)
                break
            catch e
                if attempt <= max_retries
                    wait_sec = sleep_sec * 2^(attempt - 1)
                    @warn "Batch $(batch_num) attempt $(attempt) failed: $e. Retrying in $(wait_sec)s"
                    sleep(wait_sec)
                else
                    @warn "Batch $(batch_num) failed after $(max_retries) retries: $e"
                    result = _empty_geocode_result(batch)
                end
            end
        end

        result !== nothing && push!(results, result)
        batch_num < ceil(Int, n / batch_size) && sleep(sleep_sec)
    end

    isempty(results) ? _empty_geocode_result(addresses) : vcat(results...)
end

# ── Address normalisation utilities ──────────────────────────────────────────

"""
    normalize_address(addr::String) -> String

Normalise a street address for geocoding:
- Replace common abbreviations (St→Street, Ave→Avenue, etc.)
- Remove extra whitespace
- Handle apartment/suite numbers
"""
function normalize_address(addr::String)::String
    s = strip(addr)
    # Expand common abbreviations. Patterns use a lookahead (?=\W|$) so they
    # consume the optional trailing period and stop at a non-word character.
    replacements = [
        r"\bSt\.?(?=\W|$)"i   => "Street",
        r"\bAve\.?(?=\W|$)"i  => "Avenue",
        r"\bBlvd\.?(?=\W|$)"i => "Boulevard",
        r"\bDr\.?(?=\W|$)"i   => "Drive",
        r"\bRd\.?(?=\W|$)"i   => "Road",
        r"\bLn\.?(?=\W|$)"i   => "Lane",
        r"\bCt\.?(?=\W|$)"i   => "Court",
        r"\bPl\.?(?=\W|$)"i   => "Place",
        r"\bHwy\.?(?=\W|$)"i  => "Highway",
        r"\bPkwy\.?(?=\W|$)"i => "Parkway",
        r"\bN\.?(?=\W|$)"i    => "North",
        r"\bS\.?(?=\W|$)"i    => "South",
        r"\bE\.?(?=\W|$)"i    => "East",
        r"\bW\.?(?=\W|$)"i    => "West",
        r"\bNE\b"i             => "Northeast",
        r"\bNW\b"i             => "Northwest",
        r"\bSE\b"i             => "Southeast",
        r"\bSW\b"i             => "Southwest",
        r"\bApt\.?\s*"i        => "Apt ",
        r"\bSte\.?\s*"i        => "Suite ",
        r"\s+"                 => " ",
    ]
    for (pattern, replacement) in replacements
        s = replace(s, pattern => replacement)
    end
    strip(s)
end

"""
    is_po_box(addr::String) -> Bool

Return true if the address is a P.O. Box (not geocodable to street location).
"""
function is_po_box(addr::String)::Bool
    occursin(r"P\.?\s*O\.?\s*Box\s+\d+"i, addr) ||
    occursin(r"Post\s+Office\s+Box"i, addr) ||
    occursin(r"^P\.?O\.\s*Box"i, addr)
end

"""
    is_rural_route(addr::String) -> Bool

Return true if the address is a Rural Route (RR) designation.
Rural routes often geocode poorly; flag for manual review.
"""
function is_rural_route(addr::String)::Bool
    occursin(r"^RR\s+\d+"i, addr) ||
    occursin(r"Rural\s+Route\s+\d+"i, addr) ||
    occursin(r"^HC\s+\d+"i, addr) ||   # Highway Contract Route
    occursin(r"^General\s+Delivery"i, addr)
end

"""
    standardize_state(state::String) -> String

Normalise state input: accepts full name or abbreviation, returns 2-letter FIPS abbreviation.
Returns the original string if not recognised.
"""
function standardize_state(state::String)::String
    s = strip(uppercase(state))
    # 2-letter already
    length(s) == 2 && return s

    state_map = Dict(
        "ALABAMA" => "AL", "ALASKA" => "AK", "ARIZONA" => "AZ", "ARKANSAS" => "AR",
        "CALIFORNIA" => "CA", "COLORADO" => "CO", "CONNECTICUT" => "CT",
        "DELAWARE" => "DE", "FLORIDA" => "FL", "GEORGIA" => "GA",
        "HAWAII" => "HI", "IDAHO" => "ID", "ILLINOIS" => "IL", "INDIANA" => "IN",
        "IOWA" => "IA", "KANSAS" => "KS", "KENTUCKY" => "KY", "LOUISIANA" => "LA",
        "MAINE" => "ME", "MARYLAND" => "MD", "MASSACHUSETTS" => "MA", "MICHIGAN" => "MI",
        "MINNESOTA" => "MN", "MISSISSIPPI" => "MS", "MISSOURI" => "MO", "MONTANA" => "MT",
        "NEBRASKA" => "NE", "NEVADA" => "NV", "NEW HAMPSHIRE" => "NH",
        "NEW JERSEY" => "NJ", "NEW MEXICO" => "NM", "NEW YORK" => "NY",
        "NORTH CAROLINA" => "NC", "NORTH DAKOTA" => "ND", "OHIO" => "OH",
        "OKLAHOMA" => "OK", "OREGON" => "OR", "PENNSYLVANIA" => "PA",
        "RHODE ISLAND" => "RI", "SOUTH CAROLINA" => "SC", "SOUTH DAKOTA" => "SD",
        "TENNESSEE" => "TN", "TEXAS" => "TX", "UTAH" => "UT", "VERMONT" => "VT",
        "VIRGINIA" => "VA", "WASHINGTON" => "WA", "WEST VIRGINIA" => "WV",
        "WISCONSIN" => "WI", "WYOMING" => "WY", "DISTRICT OF COLUMBIA" => "DC",
    )
    get(state_map, s, state)
end

# ── Internal helpers ──────────────────────────────────────────────────────────

function _geocoded_to_df(results::Vector{GeocodedAddress})::DataFrame
    DataFrame(
        id              = [r.id              for r in results],
        input_address   = [r.input_address   for r in results],
        matched_address = [r.matched_address for r in results],
        lat             = [r.lat             for r in results],
        lon             = [r.lon             for r in results],
        match_type      = [r.match_type      for r in results],
        tract_fips      = [r.tract_fips      for r in results],
        score           = [r.score           for r in results],
        backend         = [string(r.backend) for r in results],
    )
end

end # module Geocode
