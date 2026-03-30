# src/census_client.jl
# U.S. Census Bureau ACS API client.

using HTTP, JSON, DataFrames, CSV

const ACS_BASE = "https://api.census.gov/data"

"""
    get_acs(variables; geography="county", state=nothing, county=nothing,
             year=2022, api_key=ENV["CENSUS_API_KEY"]) -> DataFrame

Fetch American Community Survey 5-year estimates from the Census API.

**Arguments:**
- `variables`  — Vector of ACS variable codes (e.g. `["B01001_001E", "B17001_002E"]`)
- `geography`  — `"county"`, `"tract"`, `"state"`, or `"block group"`
- `state`      — 2-digit state FIPS string (e.g. `"38"` for ND); required for tract/BG
- `county`     — 3-digit county FIPS string; required for block group
- `year`       — ACS release year (default 2022)
- `api_key`    — Census API key (reads from `ENV["CENSUS_API_KEY"]` by default)

Returns a `DataFrame` with the requested variables plus geographic identifiers.

**Common variables:**
| Code | Description |
|------|-------------|
| B01001_001E | Total population |
| B17001_002E | Population below poverty level |
| B27001_001E | Total (health insurance coverage) |
| B27001_017E | Male 19-25 uninsured |
| B27001_033E | Female 19-25 uninsured |
| B19013_001E | Median household income |
| B23025_005E | Unemployed |
"""
function get_acs(variables::Vector{String};
                  geography::AbstractString = "county",
                  state::Union{Nothing, AbstractString} = nothing,
                  county::Union{Nothing, AbstractString} = nothing,
                  year::Int     = 2022,
                  api_key::AbstractString = get(ENV, "CENSUS_API_KEY", ""))::DataFrame
    vars_str = join(["NAME"; variables], ",")

    # Build the "for" and "in" clauses
    for_clause = if geography == "tract"
        "tract:*"
    elseif geography == "block group"
        "block%20group:*"
    elseif geography == "state"
        "state:*"
    else
        "county:*"
    end

    in_clause = ""
    if !isnothing(state) && geography in ("tract", "block group", "county")
        in_clause = "&in=state:$(state)"
        if !isnothing(county) && geography == "block group"
            in_clause *= "%20county:$(county)"
        end
    end

    key_clause = isempty(api_key) ? "" : "&key=$(api_key)"

    url = "$(ACS_BASE)/$(year)/acs/acs5" *
          "?get=$(vars_str)" *
          "&for=$(for_clause)" *
          in_clause *
          key_clause

    @debug "Census ACS URL: $url"

    resp = try
        HTTP.get(url; status_exception = true, readtimeout = 60)
    catch e
        error("Census ACS API request failed.\nURL: $url\nError: $(e)")
    end

    data = JSON.parse(String(resp.body))
    length(data) < 2 && return DataFrame()

    headers = Symbol.(data[1])
    rows    = [Dict(zip(headers, data[i])) for i in 2:length(data)]
    df      = DataFrame(rows)

    # Parse numeric variable columns (leave identifiers as String)
    id_cols = Set([:NAME, :state, :county, :tract, Symbol("block group")])
    for col in names(df)
        Symbol(col) in id_cols && continue
        parsed = tryparse.(Float64, coalesce.(string.(df[!, col]), ""))
        if !any(isnothing, parsed)
            df[!, col] = Float64.(parsed)
        end
    end

    # Build GEOID
    if :state in propertynames(df) && :county in propertynames(df)
        if :tract in propertynames(df)
            df.geoid = string.(df.state) .* string.(df.county) .* string.(df.tract)
        else
            df.geoid = string.(df.state) .* string.(df.county)
        end
    end

    df
end

"""
    get_acs_variables(year=2022; search=nothing) -> DataFrame

Return the full list of ACS 5-year variable codes and their labels for `year`.
Pass `search` (case-insensitive string) to filter by label.

Useful for discovering variable codes before calling `get_acs`.
"""
function get_acs_variables(year::Int = 2022;
                             search::Union{Nothing, AbstractString} = nothing)::DataFrame
    url = "$(ACS_BASE)/$(year)/acs/acs5/variables.json"
    resp = HTTP.get(url; readtimeout = 60, status_exception = true)
    data = JSON.parse(String(resp.body))

    rows = [Dict("code" => k, "label" => get(v, "label", ""),
                 "concept" => get(v, "concept", ""))
            for (k, v) in data["variables"]]
    df = DataFrame(rows)

    if !isnothing(search)
        mask = [occursin(lowercase(search), lowercase(string(r.label))) ||
                occursin(lowercase(search), lowercase(string(r.concept)))
                for r in eachrow(df)]
        df = df[mask, :]
    end

    sort!(df, :code)
    df
end
