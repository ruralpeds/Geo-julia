#!/usr/bin/env julia
# scripts/generate_report.jl
#
# Command-line rural health geographic analysis report generator.
#
# Usage:
#   julia scripts/generate_report.jl --state ND --year 2022 --output report.pdf
#
# Produces a multi-section PDF report covering:
#   1. State rural profile
#   2. Healthcare provider supply
#   3. Spatial accessibility analysis
#   4. Health outcomes geography
#   5. Social determinants of health

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using ArgParse
using DataFrames, CSV, Statistics
using CairoMakie, GeoMakie
using HealthcareGeo

# ──────────────────────────────────────────────────────────────────────────────
# CLI argument parsing
# ──────────────────────────────────────────────────────────────────────────────

function parse_args_report()
    s = ArgParseSettings(
        description = "Generate a rural health geographic analysis report for a U.S. state.",
        prog        = "generate_report.jl",
    )
    @add_arg_table! s begin
        "--state"
            help     = "Two-letter state abbreviation (e.g. ND)"
            required = true
            arg_type = String
        "--year"
            help     = "Data year for ACS and mortality data"
            arg_type = Int
            default  = 2022
        "--output"
            help    = "Output PDF file path"
            default = "rural_health_report.pdf"
        "--data-dir"
            help    = "Directory containing pre-downloaded data files"
            default = joinpath(@__DIR__, "..", "data", "raw")
    end
    return parse_args(s)
end

# ──────────────────────────────────────────────────────────────────────────────
# Report section helpers
# ──────────────────────────────────────────────────────────────────────────────

"""
    _section_title!(fig, row, col, text)

Add a bold section-title label to *fig* at grid position [row, col].
"""
function _section_title!(fig, row, col, text)
    fig[row, col] = Label(fig, text;
                           fontsize  = 18,
                           font      = :bold,
                           tellwidth = false,
                           halign    = :left)
end

"""
    _narrative(df, state) -> String

Generate a 2-3 sentence narrative summary of the rural population composition
for *state*.
"""
function _narrative(df::DataFrame, state::AbstractString)::String
    if !("is_rural_forhp" in names(df)) || !("total_population" in names(df))
        return "Rural classification data not available for automated narrative."
    end
    total_pop  = sum(df.total_population)
    rural_pop  = sum(df.total_population[df.is_rural_forhp])
    rural_pct  = round(rural_pop / total_pop * 100; digits = 1)
    n_rural    = sum(df.is_rural_forhp)
    n_total    = nrow(df)
    return "$(state) contains $(n_total) census tracts, of which $(n_rural) " *
           "($(rural_pct)% of the population) meet FORHP rural criteria. " *
           "Rural residents face distinct geographic barriers to healthcare access " *
           "that this report quantifies using spatial accessibility methods."
end

# ──────────────────────────────────────────────────────────────────────────────
# Section 1: State Rural Profile
# ──────────────────────────────────────────────────────────────────────────────

function section_rural_profile!(fig, page_row, counties_df, county_geoms, state)
    _section_title!(fig, page_row, 1:4, "Section 1: State Rural Profile — $(state)")

    # Map: RUCA classification
    if "ruca_code" in names(counties_df)
        ax = GeoAxis(fig[page_row + 1, 1:2];
                     dest  = "+proj=laea +lat_0=45 +lon_0=-96 +ellps=WGS84",
                     title = "RUCA Rural-Urban Classification")
        poly!(ax, county_geoms;
              color       = Float64.(coalesce.(counties_df.ruca_code, 0.0)),
              colormap    = :RdYlGn_r,
              strokecolor = :white,
              strokewidth = 0.4)
        Colorbar(fig[page_row + 1, 3];
                 colormap = :RdYlGn_r,
                 limits   = (1, 10),
                 label    = "RUCA Code (1=Urban → 10=Rural)",
                 width    = 15)
    end

    # Narrative label
    narrative = _narrative(counties_df, state)
    fig[page_row + 2, 1:4] = Label(fig, narrative;
                                    fontsize  = 11,
                                    tellwidth = false,
                                    halign    = :left,
                                    word_wrap = true)
end

# ──────────────────────────────────────────────────────────────────────────────
# Section 2: Healthcare Provider Supply
# ──────────────────────────────────────────────────────────────────────────────

function section_provider_supply!(fig, page_row, counties_df, county_geoms)
    _section_title!(fig, page_row, 1:4, "Section 2: Healthcare Provider Supply")

    if "active_pcp_per_100k" in names(counties_df)
        ax = GeoAxis(fig[page_row + 1, 1:2];
                     dest  = "+proj=laea +lat_0=45 +lon_0=-96 +ellps=WGS84",
                     title = "Primary Care Physicians per 100 k")
        vals = Float64.(coalesce.(counties_df.active_pcp_per_100k, 0.0))
        poly!(ax, county_geoms;
              color = vals, colormap = :YlGn,
              strokecolor = :white, strokewidth = 0.4)
        Colorbar(fig[page_row + 1, 3];
                 colormap = :YlGn,
                 limits   = (0, max(maximum(vals), 1.0)),
                 label    = "PCP per 100 k", width = 15)

        # Moran's I for provider density
        if nrow(counties_df) >= 4
            coords = hcat(coalesce.(counties_df.centroid_lat, 46.0),
                          coalesce.(counties_df.centroid_lon, -98.0))
            W = build_distance_band_weights(Float64.(coords); bandwidth_km = 100.0)
            mi = compute_morans_i(vals, W; permutations = 199)
            fig[page_row + 2, 1:4] = Label(fig,
                "Provider density Moran's I = $(round(mi.I; digits=3)), " *
                "p = $(round(mi.p_value; digits=3))";
                fontsize = 11, tellwidth = false, halign = :left)
        end
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# Section 3: Spatial Accessibility
# ──────────────────────────────────────────────────────────────────────────────

function section_accessibility!(fig, page_row, counties_df, county_geoms)
    _section_title!(fig, page_row, 1:4, "Section 3: Spatial Accessibility Analysis")

    if "access_2sfca" in names(counties_df)
        ax = GeoAxis(fig[page_row + 1, 1:2];
                     dest  = "+proj=laea +lat_0=45 +lon_0=-96 +ellps=WGS84",
                     title = "E2SFCA Accessibility Score")
        vals = Float64.(coalesce.(counties_df.access_2sfca, 0.0))
        poly!(ax, county_geoms;
              color = vals, colormap = :Blues,
              strokecolor = :white, strokewidth = 0.4)
        Colorbar(fig[page_row + 1, 3];
                 colormap = :Blues,
                 limits   = (minimum(vals), max(maximum(vals), 1e-9)),
                 label    = "Accessibility Score", width = 15)

        # Access desert statistics
        p10 = quantile(vals, 0.10)
        desert_pop = "access_2sfca" in names(counties_df) ?
            sum(coalesce.(counties_df.total_population, 0.0)[vals .< p10]) : NaN
        label_txt = isnan(desert_pop) ? "Access desert statistics unavailable." :
            "Population in access desert (< p10 accessibility): $(round(Int, desert_pop)) persons."
        fig[page_row + 2, 1:4] = Label(fig, label_txt;
                                        fontsize = 11, tellwidth = false, halign = :left)
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# Section 4: Health Outcomes Geography
# ──────────────────────────────────────────────────────────────────────────────

function section_health_outcomes!(fig, page_row, counties_df, county_geoms)
    _section_title!(fig, page_row, 1:4, "Section 4: Health Outcomes Geography")

    if "cvd_mortality_rate" in names(counties_df)
        vals = Float64.(coalesce.(counties_df.cvd_mortality_rate, 0.0))
        ax1 = GeoAxis(fig[page_row + 1, 1:2];
                      dest  = "+proj=laea +lat_0=45 +lon_0=-96 +ellps=WGS84",
                      title = "Age-Adjusted CVD Mortality Rate")
        poly!(ax1, county_geoms;
              color = vals, colormap = :Reds,
              strokecolor = :white, strokewidth = 0.4)
        Colorbar(fig[page_row + 1, 3];
                 colormap = :Reds,
                 limits   = (minimum(vals), maximum(vals)),
                 label    = "CVD Deaths per 100 k", width = 15)
    end

    if "lisa_cluster" in names(counties_df)
        cluster_map = Dict("HH" => 4.0, "HL" => 3.0, "LH" => 2.0, "LL" => 1.0, "NS" => 0.0)
        cvals = Float64.([get(cluster_map, c, 0.0) for c in coalesce.(counties_df.lisa_cluster, "NS")])
        ax2 = GeoAxis(fig[page_row + 1, 4];
                      dest  = "+proj=laea +lat_0=45 +lon_0=-96 +ellps=WGS84",
                      title = "CVD LISA Clusters")
        poly!(ax2, county_geoms;
              color = cvals, colormap = :RdBu,
              strokecolor = :white, strokewidth = 0.4)
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# Section 5: Social Determinants
# ──────────────────────────────────────────────────────────────────────────────

function section_sdoh!(fig, page_row, counties_df, county_geoms)
    _section_title!(fig, page_row, 1:4, "Section 5: Social Determinants of Health")

    sdoh_vars = [
        (:pct_poverty,      "Poverty Rate (%)",          :Oranges),
        (:uninsured_pct,    "Uninsurance Rate (%)",      :Purples),
    ]

    col_offset = 1
    for (var, label, cmap) in sdoh_vars
        var in propertynames(counties_df) || continue
        vals = Float64.(coalesce.(counties_df[!, var], 0.0))
        ax = GeoAxis(fig[page_row + 1, col_offset:(col_offset + 1)];
                     dest  = "+proj=laea +lat_0=45 +lon_0=-96 +ellps=WGS84",
                     title = label)
        poly!(ax, county_geoms;
              color = vals, colormap = cmap,
              strokecolor = :white, strokewidth = 0.4)
        Colorbar(fig[page_row + 2, col_offset];
                 colormap = cmap,
                 limits   = (minimum(vals), max(maximum(vals), 1.0)),
                 label    = label, width = 12, height = Relative(0.6))
        col_offset += 2
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# Main report assembly
# ──────────────────────────────────────────────────────────────────────────────

function generate_report(state::AbstractString, year::Int, outfile::AbstractString,
                          data_dir::AbstractString)
    @info "Generating rural health report for $(state) ($(year)) → $(outfile)"
    t0 = time()

    # ── Load data ────────────────────────────────────────────────────────────
    # Download TIGER county boundaries
    shp_path = download_tiger_counties(2023)
    all_counties = GeoDataFrames.read(shp_path)

    # Filter to requested state using STUSPS or STATEFP
    state_col = "STUSPS" in names(all_counties) ? :STUSPS : :STATEFP
    mask = all_counties[!, state_col] .== state
    counties_df  = all_counties[mask, :]
    county_geoms = counties_df.geometry

    nrow(counties_df) == 0 &&
        error("No counties found for state '$state'. Check state abbreviation.")

    @info "Loaded $(nrow(counties_df)) counties for $(state)."

    # ── Build multi-page figure ───────────────────────────────────────────────
    fig = Figure(resolution = (1600, 4800), fontsize = 12)

    # Page header
    fig[1, 1:4] = Label(fig,
        "Rural Health Geographic Analysis Report — $(state) — $(year)";
        fontsize = 24, font = :bold, tellwidth = false)
    fig[2, 1:4] = Label(fig,
        "Generated $(Dates.format(now(), "yyyy-mm-dd HH:MM")) | Source: HRSA, Census, CDC WONDER";
        fontsize = 10, tellwidth = false, color = :gray)

    # Sections (each takes ~3 figure rows)
    section_rural_profile!(fig,  3,  counties_df, county_geoms, state)
    section_provider_supply!(fig, 7,  counties_df, county_geoms)
    section_accessibility!(fig,  11, counties_df, county_geoms)
    section_health_outcomes!(fig, 15, counties_df, county_geoms)
    section_sdoh!(fig,           19, counties_df, county_geoms)

    # Footer
    fig[22, 1:4] = Label(fig,
        "Data sources: HRSA Data Warehouse | U.S. Census Bureau TIGER/Line | " *
        "CDC WONDER | USDA ERS RUCA Codes";
        fontsize = 9, color = :gray, tellwidth = false)

    save(outfile, fig; pt_per_unit = 1)
    elapsed = round(time() - t0; digits = 1)
    @info "Report saved to $(outfile) in $(elapsed)s"
end

# ──────────────────────────────────────────────────────────────────────────────
# Entry point
# ──────────────────────────────────────────────────────────────────────────────

function main()
    args = parse_args_report()
    generate_report(args["state"], args["year"], args["output"], args["data-dir"])
end

main()
