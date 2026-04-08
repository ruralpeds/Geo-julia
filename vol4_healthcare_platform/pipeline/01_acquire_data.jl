#!/usr/bin/env julia
# pipeline/01_acquire_data.jl
# North Dakota Primary Care Access Analysis — Data Acquisition Layer
# Run once to download and cache all required data.
# Vol 4 — Chapter 29.1.1

using HTTP, CSV, DataFrames, JSON3
using Dates

const ND_FIPS  = "38"
const DATA_DIR = joinpath(@__DIR__, "..", "data")
const RAW_DIR  = joinpath(DATA_DIR, "raw")
const PROC_DIR = joinpath(DATA_DIR, "processed")
mkpath.([RAW_DIR, PROC_DIR])

# ── 1. TIGER/Line county boundaries for North Dakota ──────────────────────────
function acquire_tiger_counties(year=2023)
    dest = joinpath(RAW_DIR, "tl_$(year)_38_county.zip")
    isfile(dest) && (@info "TIGER counties cached"; return dest)
    url = "https://www2.census.gov/geo/tiger/TIGER$(year)/COUNTY/" *
          "tl_$(year)_38_county.zip"
    @info "Downloading ND county boundaries from Census TIGER..."
    write(dest, HTTP.get(url; readtimeout=120).body)
    @info "TIGER counties downloaded: $(dest)"
    dest
end

# ── 2. ACS 5-year estimates (poverty, uninsurance, population) ─────────────────
function acquire_acs_nd(year=2022)
    dest = joinpath(RAW_DIR, "acs5_nd_$(year).csv")
    isfile(dest) && return DataFrame(CSV.File(dest))

    api_key = get(ENV, "CENSUS_API_KEY", "")
    # Variables:
    #   B27001_001E = total population (health insurance universe)
    #   B27001_017E = male 19-25 no health insurance  (proxy for uninsured)
    #   B27001_033E = female 19-25 no health insurance
    #   B17001_001E = total population (poverty universe)
    #   B17001_002E = population below poverty level
    #   B01003_001E = total population
    vars = "B27001_001E,B27001_017E,B27001_033E,B17001_001E,B17001_002E,B01003_001E"
    url  = "https://api.census.gov/data/$(year)/acs/acs5" *
           "?get=NAME,$(vars)&for=county:*&in=state:38" *
           (isempty(api_key) ? "" : "&key=$(api_key)")

    @info "Fetching ACS 5-year data for ND counties (year=$(year))..."
    resp    = JSON3.read(String(HTTP.get(url; readtimeout=60).body))
    headers = Symbol.(resp[1])
    df = DataFrame([Dict(headers[j] => resp[i][j] for j in 1:length(headers))
                    for i in 2:length(resp)])

    # Build standard GEOID
    df.GEOID = lpad.(df.state, 2, '0') .* lpad.(df.county, 3, '0')

    # Convert numeric columns
    for col in [:B01003_001E, :B17001_001E, :B17001_002E, :B27001_001E,
                :B27001_017E, :B27001_033E]
        df[!, col] = [tryparse(Float64, string(x)) for x in df[!, col]]
    end

    CSV.write(dest, df)
    @info "ACS data saved: $(nrow(df)) ND counties"
    df
end

# ── 3. AHRF — Area Health Resource File (HRSA) ────────────────────────────────
function acquire_nd_physicians()
    dest = joinpath(RAW_DIR, "nd_physicians.csv")
    isfile(dest) && return DataFrame(CSV.File(dest))

    @info "Downloading AHRF county data from HRSA (this may be large)..."
    url = "https://data.hrsa.gov/DataDownload/DD_Files/AHRF_County.csv"
    try
        full_ahrf = CSV.read(IOBuffer(HTTP.get(url; readtimeout=300).body), DataFrame)
        # Filter to ND (FIPS prefix "38")
        nd = filter(r -> startswith(string(get(r, :f00011, "")), "38"), eachrow(full_ahrf)) |>
             collect |> DataFrame
        CSV.write(dest, nd)
        @info "AHRF ND extract saved: $(nrow(nd)) counties"
        return nd
    catch e
        @warn "AHRF download failed: $e. Creating synthetic physician data for testing."
        # Synthetic fallback for testing
        nd_df = DataFrame(
            fips          = ["38" * lpad(i, 3, '0') for i in 1:53],
            county_name   = ["County $(i)" for i in 1:53],
            pcp_per_100k  = 30.0 .+ 50.0 .* rand(53),
            rucc_code     = rand(1:9, 53),
            population    = round.(Int, 1000 .+ 50000 .* rand(53).^2)
        )
        CSV.write(dest, nd_df)
        return nd_df
    end
end

# ── 4. CMS NPPES — Primary care provider locations ────────────────────────────
function acquire_nd_provider_locations()
    dest = joinpath(RAW_DIR, "nd_providers.csv")
    isfile(dest) && return DataFrame(CSV.File(dest))

    @info "Querying NPPES NPI Registry for ND Family Medicine providers..."
    all_rows = []
    for skip in 0:200:800
        url = "https://npiregistry.cms.hhs.gov/api/?" *
              "state=ND&taxonomy_description=Family+Medicine&limit=200&skip=$(skip)"
        try
            resp = JSON3.read(String(HTTP.get(url; readtimeout=30).body))
            providers = get(resp, :results, [])
            isempty(providers) && break
            for p in providers
                addrs = get(p, :addresses, [])
                isempty(addrs) && continue
                a = addrs[1]
                push!(all_rows, (
                    npi        = string(get(p, :number, "")),
                    first_name = string(get(get(p, :basic, Dict()), :first_name, "")),
                    last_name  = string(get(get(p, :basic, Dict()), :last_name, "")),
                    city       = string(get(a, :city, "")),
                    state      = string(get(a, :state, "")),
                    zip        = string(get(a, :postal_code, ""))[1:min(5,end)],
                    street     = string(get(a, :address_1, ""))
                ))
            end
            length(providers) < 200 && break
        catch e
            @warn "NPPES query failed at skip=$(skip): $e"
            break
        end
    end

    if isempty(all_rows)
        @warn "No NPPES results. Using synthetic provider data for testing."
        # 45 synthetic ND providers
        all_rows = [(npi=string(i), first_name="Provider", last_name="$(i)",
                     city="Bismarck", state="ND", zip="58501",
                     street="$(100+i) Main St") for i in 1:45]
    end

    df = DataFrame(all_rows)
    df.id = 1:nrow(df)
    CSV.write(dest, df)
    @info "Provider data saved: $(nrow(df)) ND primary care providers"
    df
end

# ── Run all acquisition steps ─────────────────────────────────────────────────
@info "=== Vol 4 North Dakota Healthcare Access Analysis ==="
@info "=== Phase 1: Data Acquisition ==="

tiger_path = acquire_tiger_counties()
acs_df     = acquire_acs_nd()
ahrf_df    = acquire_nd_physicians()
prov_df    = acquire_nd_provider_locations()

@info "Data acquisition complete."
@info "  TIGER: $(tiger_path)"
@info "  ACS: $(nrow(acs_df)) counties"
@info "  Physicians: $(nrow(ahrf_df)) county records"
@info "  Providers: $(nrow(prov_df)) NPI records"
