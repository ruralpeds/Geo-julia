# src/data/download.jl
# Automated downloading and caching of HRSA, Census, TIGER, and USDA data.

using HTTP, JSON, CSV, DataFrames, Dates, ZipFile, XLSX

# ──────────────────────────────────────────────────────────────────────────────
# Internal helpers
# ──────────────────────────────────────────────────────────────────────────────

"""Return the project data/raw/ root, creating it if necessary."""
function _raw_dir()
    d = joinpath(dirname(dirname(@__DIR__)), "data", "raw")
    mkpath(d)
    d
end

"""
    _manifest_path(subdir) -> String

Path to the manifest.json file inside a raw data subdirectory.
"""
_manifest_path(subdir::AbstractString) = joinpath(_raw_dir(), subdir, "manifest.json")

"""
    _read_manifest(subdir) -> Dict

Read the manifest for *subdir*, returning an empty Dict if it does not exist.
"""
function _read_manifest(subdir::AbstractString)
    path = _manifest_path(subdir)
    isfile(path) ? JSON.parsefile(path) : Dict{String,Any}()
end

"""
    _write_manifest(subdir, url, local_path)

Write / update the manifest for *subdir* recording download URL, local path,
and current timestamp.
"""
function _write_manifest(subdir::AbstractString, url::AbstractString,
                          local_path::AbstractString)
    manifest = _read_manifest(subdir)
    manifest[basename(local_path)] = Dict(
        "url"            => url,
        "local_path"     => local_path,
        "downloaded_at"  => string(now()),
    )
    open(_manifest_path(subdir), "w") do io
        JSON.print(io, manifest, 2)
    end
end

"""
    _cache_valid(local_path; max_age_days=365) -> Bool

Return `true` if *local_path* exists, has size > 0, and is younger than
*max_age_days*.
"""
function _cache_valid(local_path::AbstractString; max_age_days::Int = 365)
    isfile(local_path) || return false
    filesize(local_path) > 0 || return false
    mtime = Dates.unix2datetime(stat(local_path).mtime)
    age = now() - mtime
    Dates.value(age) / (1000 * 60 * 60 * 24) < max_age_days
end

"""
    _download_file(url, local_path; subdir)

Download *url* to *local_path*, writing the manifest entry for *subdir*.
Raises an informative error if the download fails.
"""
function _download_file(url::AbstractString, local_path::AbstractString;
                         subdir::AbstractString)
    @info "Downloading $(basename(local_path)) from $url"
    try
        resp = HTTP.get(url; status_exception = true)
        write(local_path, resp.body)
    catch e
        error("Failed to download $(url)\n" *
              "Check network connectivity and retry.\n" *
              "Original error: $(e)")
    end
    filesize(local_path) > 0 || error("Downloaded file is empty: $local_path")
    _write_manifest(subdir, url, local_path)
    local_path
end

"""
    _unzip(zip_path, dest_dir) -> String

Extract *zip_path* into *dest_dir*.  Returns *dest_dir*.
"""
function _unzip(zip_path::AbstractString, dest_dir::AbstractString)
    mkpath(dest_dir)
    ZipFile.Reader(zip_path) do z
        for f in z.files
            out = joinpath(dest_dir, f.name)
            if endswith(f.name, '/')
                mkpath(out)
            else
                mkpath(dirname(out))
                open(out, "w") do io
                    write(io, read(f))
                end
            end
        end
    end
    dest_dir
end

# ──────────────────────────────────────────────────────────────────────────────
# Public download functions
# ──────────────────────────────────────────────────────────────────────────────

"""
    download_tiger_counties(year; force_refresh=false) -> String

Download the national county TIGER/Line shapefile for *year* from the Census
Bureau.  Caches the result in `data/raw/tiger/`.  Returns the path to the
local `.shp` file.
"""
function download_tiger_counties(year::Int = 2023; force_refresh::Bool = false)
    subdir    = "tiger"
    dest_dir  = mkpath(joinpath(_raw_dir(), subdir, "county_$(year)"))
    shp_name  = "tl_$(year)_us_county.shp"
    shp_path  = joinpath(dest_dir, shp_name)

    if !force_refresh && _cache_valid(shp_path)
        @info "Using cached TIGER county shapefile: $shp_path"
        return shp_path
    end

    zip_name  = "tl_$(year)_us_county.zip"
    url       = "https://www2.census.gov/geo/tiger/TIGER$(year)/COUNTY/$(zip_name)"
    zip_path  = joinpath(dest_dir, zip_name)

    _download_file(url, zip_path; subdir)
    _unzip(zip_path, dest_dir)
    rm(zip_path; force = true)

    isfile(shp_path) || error("Expected shapefile not found after extraction: $shp_path")
    shp_path
end

"""
    download_ruca_codes(; force_refresh=false) -> DataFrame

Download 2010-revised RUCA codes from USDA ERS and return a DataFrame with
columns: fips_tract, ruca_primary, ruca_secondary, state_fips, county_fips.
"""
function download_ruca_codes(; force_refresh::Bool = false)
    subdir   = "usda"
    dest_dir = mkpath(joinpath(_raw_dir(), subdir))
    filename = "ruca2010revised.xlsx"
    local_path = joinpath(dest_dir, filename)

    if !force_refresh && _cache_valid(local_path)
        @info "Using cached RUCA codes: $local_path"
    else
        url = "https://www.ers.usda.gov/webdocs/DataFiles/53241/$(filename)"
        _download_file(url, local_path; subdir)
    end

    # Parse XLSX — data starts on row 2 (row 1 = header)
    xf  = XLSX.readxlsx(local_path)
    sh  = xf[XLSX.sheetnames(xf)[1]]
    raw = XLSX.eachtablerow(sh)

    rows = DataFrame(raw)
    # Normalise expected column names (case-insensitive)
    rename!(rows, Dict(n => lowercase(string(n)) for n in names(rows)))

    # Map to standard schema
    return DataFrame(
        fips_tract      = string.(rows[:, "select zip code tabulation area (zcta)"] isa AbstractVector ?
                              rows[:, findfirst(c -> occursin("fips", lowercase(c)), names(rows))] :
                              rows[:, 1]),
        ruca_primary    = rows[:, findfirst(c -> occursin("primary", lowercase(c)), names(rows))],
        ruca_secondary  = rows[:, findfirst(c -> occursin("secondary", lowercase(c)), names(rows))],
        state_fips      = lpad.(string.(floor.(Int,
                              rows[:, findfirst(c -> occursin("state", lowercase(c)), names(rows))])),
                              2, "0"),
        county_fips     = lpad.(string.(floor.(Int,
                              rows[:, findfirst(c -> occursin("county", lowercase(c)), names(rows))])),
                              3, "0"),
    )
end

"""
    download_hpsa_shapefile(; force_refresh=false) -> DataFrame

Download the current primary-care HPSA data file from HRSA and return a
spatial DataFrame with a geometry column built from HPS_LAT / HPS_LON.
"""
function download_hpsa_shapefile(; force_refresh::Bool = false)
    subdir     = "hrsa"
    dest_dir   = mkpath(joinpath(_raw_dir(), subdir))
    filename   = "BCD_HPSA_FCT_DET_PC.xlsx"
    local_path = joinpath(dest_dir, filename)

    if !force_refresh && _cache_valid(local_path)
        @info "Using cached HPSA file: $local_path"
    else
        url = "https://data.hrsa.gov/DataDownload/DD_Files/$(filename)"
        _download_file(url, local_path; subdir)
    end

    xf  = XLSX.readxlsx(local_path)
    sh  = xf[XLSX.sheetnames(xf)[1]]
    df  = DataFrame(XLSX.eachtablerow(sh))

    # Build point geometries from lat / lon columns
    lat_col = findfirst(c -> occursin("lat", lowercase(c)), names(df))
    lon_col = findfirst(c -> occursin("lon", lowercase(c)), names(df))

    if !isnothing(lat_col) && !isnothing(lon_col)
        df.geometry = ArchGDAL.createpoint.(
            Float64.(coalesce.(df[:, lon_col], NaN)),
            Float64.(coalesce.(df[:, lat_col], NaN)),
        )
    end

    df
end

"""
    fetch_acs_insurance_coverage(state_fips, year=2022;
                                  api_key=ENV["CENSUS_API_KEY"]) -> DataFrame

Fetch uninsurance rates by census tract from the ACS 5-year estimates.
Returns a DataFrame with columns: geoid, total_pop, uninsured_n, uninsured_pct.
"""
function fetch_acs_insurance_coverage(state_fips::AbstractString,
                                       year::Int = 2022;
                                       api_key::String = get(ENV, "CENSUS_API_KEY", ""))
    if isempty(api_key)
        @warn "CENSUS_API_KEY not set; Census API may rate-limit unauthenticated requests."
    end

    variables = ["B27001_001E", "B27001_017E", "B27001_033E"]
    vars_str  = join(["NAME"; variables], ",")
    url = "https://api.census.gov/data/$(year)/acs/acs5" *
          "?get=$(vars_str)" *
          "&for=tract:*" *
          "&in=state:$(state_fips)" *
          (isempty(api_key) ? "" : "&key=$(api_key)")

    resp = HTTP.get(url; status_exception = true)
    data = JSON.parse(String(resp.body))

    headers = Symbol.(data[1])
    rows = [Dict(zip(headers, data[i])) for i in 2:length(data)]
    raw  = DataFrame(rows)

    total   = parse.(Float64, coalesce.(string.(raw.B27001_001E), "0"))
    unins_m = parse.(Float64, coalesce.(string.(raw.B27001_017E), "0"))
    unins_f = parse.(Float64, coalesce.(string.(raw.B27001_033E), "0"))
    unins_n = unins_m .+ unins_f

    DataFrame(
        geoid         = string.(raw.state) .* string.(raw.county) .* string.(raw.tract),
        total_pop     = total,
        uninsured_n   = unins_n,
        uninsured_pct = ifelse.(total .> 0, unins_n ./ total .* 100, missing),
    )
end

"""
    load_ahrf(filepath) -> DataFrame

Load an Area Health Resources Files (AHRF) SAS transport file and return a
DataFrame with standardised column names:
county_fips, active_pcp_per_100k, rucc, pct_poverty,
median_income, total_population.
"""
function load_ahrf(filepath::AbstractString)::DataFrame
    # ReadStatTables is an optional heavy dependency; load lazily
    ReadStatTables = Base.require(Base.PkgId(
        Base.UUID("52522f7a-9570-4e34-8ac6-c4953e69b0bb"), "ReadStatTables"))

    raw = ReadStatTables.read_sas(filepath)
    df  = DataFrame(raw)

    rename!(df, Dict(
        :F11       => :county_fips,
        :F1522086  => :active_pcp_per_100k,
        :F1522166  => :rucc,
        :F1306105  => :pct_poverty,
        :F0453053  => :median_income,
        :F0453048  => :total_population,
    ))

    select(df, :county_fips, :active_pcp_per_100k, :rucc,
               :pct_poverty, :median_income, :total_population)
end
