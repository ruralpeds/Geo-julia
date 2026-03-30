#!/usr/bin/env julia
# scripts/run_state_analysis.jl
#
# Full state-level healthcare geographic analysis pipeline.
# Integrates HealthcareGeo, SpatialStats, and PopulationData.
#
# Usage:
#   julia scripts/run_state_analysis.jl --state ND --year 2022
#   julia scripts/run_state_analysis.jl --state MT --output mt_analysis.csv

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using ArgParse
using DataFrames, Statistics, Dates
using GeoDataFrames
using HealthcareGeo, SpatialStats, PopulationData

function parse_cli()
    s = ArgParseSettings(description = "Run full-state healthcare GIS analysis.")
    @add_arg_table! s begin
        "--state"
            help = "Two-letter state abbreviation"; required = true; arg_type = String
        "--year"
            help = "ACS data year"; arg_type = Int; default = 2022
        "--catchment"
            help = "E2SFCA catchment radius (km)"; arg_type = Float64; default = 60.0
        "--output"
            help = "Output CSV for results"; default = "analysis_results.csv"
        "--report"
            help = "Output PDF report"; default = "state_report.pdf"
    end
    parse_args(s)
end

# ──────────────────────────────────────────────────────────────────────────────

function run_state_analysis(state::String, year::Int,
                             catchment_km::Float64,
                             csv_out::String,
                             pdf_out::String)
    t0 = time()
    @info "=== Healthcare GIS Analysis: $(state) ($(year)) ==="

    # 1. Geographic boundaries
    @info "Loading county boundaries…"
    shp = HealthcareGeo.download_tiger_counties(2023)
    all_counties = GeoDataFrames.read(shp)
    col = "STUSPS" in names(all_counties) ? :STUSPS : :STATEFP
    counties = filter(r -> r[col] == state, all_counties)
    @info "  $(nrow(counties)) counties"

    # 2. Spatial weights
    @info "Building spatial weights (distance band, 150 km)…"
    centroids = [(
        (GeoInterface.extent(g).Y[1] + GeoInterface.extent(g).Y[2]) / 2,
        (GeoInterface.extent(g).X[1] + GeoInterface.extent(g).X[2]) / 2,
    ) for g in counties.geometry]
    coords = Float64.(hcat(first.(centroids), last.(centroids)))
    w = SpatialStats.distance_weights(
            DataFrame(geometry = counties.geometry), 150.0)

    # 3. Synthetic provider density (replace with AHRF in production)
    @info "Computing provider density (synthetic — replace with AHRF)…"
    n = nrow(counties)
    provider_density = 5.0 .* rand(n) .+ 1.0
    counties.provider_density = provider_density

    # 4. Moran's I for provider density
    @info "Computing Moran's I…"
    morans = SpatialStats.moran(provider_density, w; permutations = 499)
    @info "  Moran's I = $(round(morans.I; digits=3)), p = $(round(morans.p_value; digits=3))"

    # 5. LISA clusters
    @info "Computing LISA clusters…"
    lisa_res = SpatialStats.lisa(provider_density, w; permutations = 499, alpha = 0.05)
    counties.lisa_cluster = String.(lisa_res.cluster_type)
    hh = sum(lisa_res.cluster_type .== :HH)
    ll = sum(lisa_res.cluster_type .== :LL)
    @info "  HH hot spots: $(hh), LL cold spots: $(ll)"

    # 6. E2SFCA accessibility
    @info "Computing E2SFCA accessibility (catchment = $(catchment_km) km)…"
    providers = DataFrame(lat = first.(centroids), lon = last.(centroids),
                           supply = provider_density)
    pop_locs  = DataFrame(
        id         = string.(1:n),
        lat        = first.(centroids),
        lon        = last.(centroids),
        population = fill(1000.0, n),
    )
    access = HealthcareGeo.e2sfca(providers, pop_locs, catchment_km;
                                   decay = :gaussian, sigma_km = catchment_km / 3)
    counties.access_2sfca = access.accessibility
    p10 = quantile(access.accessibility, 0.10)
    pct_desert = round(sum(access.accessibility .< p10) / n * 100; digits = 1)
    @info "  Mean accessibility: $(round(mean(access.accessibility); digits=4))"
    @info "  Access desert (< p10): $(pct_desert)% of counties"

    # 7. ACS demographics (Census API)
    @info "Fetching ACS demographics ($(year))…"
    state_fips = get(Dict("ND"=>"38","MT"=>"30","SD"=>"46","WY"=>"56",
                           "ID"=>"16","MN"=>"27","NE"=>"31","IA"=>"19",
                           "WI"=>"55","ME"=>"23","VT"=>"50","WV"=>"54",
                           "MS"=>"28","AR"=>"05","KS"=>"20"), state, "00")

    if state_fips != "00"
        try
            acs = PopulationData.get_acs(
                ["B01001_001E", "B17001_002E", "B19013_001E"];
                geography = "county", state = state_fips, year = year)
            @info "  ACS data loaded: $(nrow(acs)) counties"
        catch e
            @warn "ACS API unavailable: $(e)"
        end
    end

    # 8. Save results
    @info "Saving results to $(csv_out)…"
    results = select(counties, Not(:geometry))
    CSV.write(csv_out, results)

    # 9. Generate PDF report
    @info "Generating PDF report to $(pdf_out)…"
    try
        HealthcareGeo.generate_report(state, year, pdf_out, "data/raw")
    catch e
        @warn "PDF report generation failed (may need GDAL libraries): $(e)"
    end

    elapsed = round(time() - t0; digits = 1)
    @info "=== Analysis complete in $(elapsed)s ==="
    @info "Moran's I summary: I=$(round(morans.I;digits=3)), p=$(round(morans.p_value;digits=3))"
    @info "LISA: HH=$(hh), LL=$(ll) | Access desert: $(pct_desert)%"
end

# Entry point
args = parse_cli()
run_state_analysis(args["state"], args["year"], args["catchment"],
                    args["output"], args["report"])
