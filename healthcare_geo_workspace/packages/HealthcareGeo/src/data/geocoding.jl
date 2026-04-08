# src/data/geocoding.jl
# U.S. address geocoding via the Census Bureau Geocoder REST API.
# No external geocoding package required — uses HTTP.jl + CSV.jl.

using HTTP, CSV, DataFrames

const CENSUS_GEOCODER_URL =
    "https://geocoding.geo.census.gov/geocoder/geographies/addressbatch"

"""
    census_geocode_batch(addresses; vintage="Current") -> DataFrame

Geocode U.S. addresses using the Census Bureau Geocoder batch API.

**Input DataFrame columns (required):**
`id`, `street`, `city`, `state`, `zip`

**Returns a DataFrame with additional columns:**
`lat`, `lon`, `match_type`, `matched_address`, `tract_fips`

- Maximum batch size: 1,000 addresses per call.
- No API key required.  Rate limits are generous for research use.
- `match_type`: `"Exact"`, `"Non_Exact"`, or missing (no match).

For lists larger than 1,000 addresses use `geocode_all()`.
"""
function census_geocode_batch(addresses::DataFrame;
                               vintage::AbstractString = "Current")::DataFrame
    nrow(addresses) > 1000 &&
        error("Batch size limit is 1,000 addresses per request.  " *
              "Use geocode_all() for larger lists.")

    # Format as CSV payload
    csv_buf  = IOBuffer()
    CSV.write(csv_buf, select(addresses, :id, :street, :city, :state, :zip))
    csv_bytes = take!(csv_buf)

    resp = try
        HTTP.post(CENSUS_GEOCODER_URL, [],
            HTTP.Form([
                "addressFile" => HTTP.Multipart(
                    "addresses.csv", IOBuffer(csv_bytes), "text/csv"),
                "benchmark" => "Public_AR_Current",
                "vintage"   => vintage,
            ]); status_exception = true)
    catch e
        error("Census Geocoder API failed.\nError: $(e)")
    end

    # Parse the response CSV
    result_raw = String(resp.body)
    isempty(strip(result_raw)) && return DataFrame()

    io   = IOBuffer(result_raw)
    cols = [:id, :input_address, :match, :match_type, :matched_address,
            :lon_lat, :tiger_line_id, :side, :state_fips, :county_fips,
            :tract, :block]
    raw  = CSV.read(io, DataFrame;
                    header       = false,
                    silencewarnings = true,
                    types        = Dict(1 => String))
    # Rename only the columns that exist
    n_actual = ncol(raw)
    rename!(raw, cols[1:n_actual])

    # Parse lon/lat from combined column "lon,lat"
    if :lon_lat in propertynames(raw)
        raw.lon = map(r -> begin
            v = get(r, :lon_lat, missing)
            !ismissing(v) && !isempty(string(v)) ?
                tryparse(Float64, split(string(v), ",")[1]) : missing
        end, eachrow(raw))
        raw.lat = map(r -> begin
            v = get(r, :lon_lat, missing)
            !ismissing(v) && !isempty(string(v)) && length(split(string(v), ",")) >= 2 ?
                tryparse(Float64, split(string(v), ",")[2]) : missing
        end, eachrow(raw))
    end

    # Build 11-digit census tract FIPS
    if :state_fips in propertynames(raw) && :county_fips in propertynames(raw) &&
       :tract in propertynames(raw)
        raw.tract_fips = map(r -> begin
            s, c, t = get(r, :state_fips, missing),
                      get(r, :county_fips, missing),
                      get(r, :tract, missing)
            any(ismissing, [s, c, t]) ? missing :
                lpad(string(s), 2, "0") * lpad(string(c), 3, "0") * lpad(string(t), 6, "0")
        end, eachrow(raw))
    end

    return raw
end

"""
    geocode_all(addresses; batch_size=500, sleep_sec=1.5) -> DataFrame

Geocode an arbitrarily large address list by splitting into batches
and calling `census_geocode_batch` sequentially with a brief pause
between requests to respect rate limits.
"""
function geocode_all(addresses::DataFrame;
                      batch_size::Int    = 500,
                      sleep_sec::Float64 = 1.5)::DataFrame
    n       = nrow(addresses)
    batches = [addresses[i:min(i + batch_size - 1, n), :]
               for i in 1:batch_size:n]
    results = DataFrame[]

    for (k, batch) in enumerate(batches)
        @info "Geocoding batch $(k)/$(length(batches)) ($(nrow(batch)) addresses)…"
        push!(results, census_geocode_batch(batch))
        k < length(batches) && sleep(sleep_sec)
    end

    isempty(results) ? DataFrame() : vcat(results...)
end
