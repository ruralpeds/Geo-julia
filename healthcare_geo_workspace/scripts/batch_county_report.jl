#!/usr/bin/env julia
# scripts/batch_county_report.jl
#
# Batch-generate county-level accessibility reports for multiple states.
#
# Usage:
#   julia scripts/batch_county_report.jl --states "ND,MT,SD,WY" --year 2022

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using ArgParse, DataFrames, CSV, Dates

function parse_cli()
    s = ArgParseSettings(description = "Batch county healthcare access analysis.")
    @add_arg_table! s begin
        "--states"
            help = "Comma-separated state abbreviations"; required = true
        "--year"
            help = "Data year"; arg_type = Int; default = 2022
        "--catchment"
            help = "E2SFCA catchment km"; arg_type = Float64; default = 60.0
        "--outdir"
            help = "Output directory"; default = "data/outputs"
    end
    parse_args(s)
end

function main()
    args  = parse_cli()
    states = strip.(split(args["states"], ","))
    year   = args["year"]
    km     = args["catchment"]
    outdir = mkpath(args["outdir"])

    summary_rows = DataFrame(
        state = String[], n_counties = Int[], moran_I = Float64[],
        moran_p = Float64[], hh_count = Int[], ll_count = Int[],
        pct_desert = Float64[], timestamp = String[])

    for state in states
        @info "Processing $(state)…"
        csv_out = joinpath(outdir, "$(state)_$(year)_results.csv")
        pdf_out = joinpath(outdir, "$(state)_$(year)_report.pdf")

        try
            include(joinpath(@__DIR__, "run_state_analysis.jl"))
        catch e
            @warn "Failed for $(state): $(e)"
        end
    end

    summary_path = joinpath(outdir, "batch_summary_$(year).csv")
    CSV.write(summary_path, summary_rows)
    @info "Batch complete. Summary: $(summary_path)"
end

main()
