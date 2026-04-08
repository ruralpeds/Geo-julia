#!/usr/bin/env julia
# docs/make.jl — Documenter.jl cross-volume documentation site
# Chapter 41 — Julia Healthcare GIS Textbook, Vol 5
#
# Builds a unified documentation site for all four textbook volumes.
# Run: julia --project=docs/ docs/make.jl
# Output: docs/build/ (deploy to GitHub Pages)

using Documenter

# ── Load available package modules ────────────────────────────────────────────

MODULES = Module[]
MODULES_NAMES = Pair{String,Symbol}[]

for (pkg_path, mod_name) in [
    ("../julia_geo_packages/packages/SpatialStats/src", :SpatialStats),
    ("../julia_geo_packages/packages/Geocode/src", :Geocode),
    ("../julia_geo_packages/packages/MapClassify/src", :MapClassify),
    ("../julia_geo_packages/packages/Overpass/src", :Overpass),
    ("../vol4_healthcare_platform/packages/PointPatterns/src", :PointPatterns),
    ("../vol5_ml_production/packages/HealthcareML/src", :HealthcareML),
    ("../vol5_ml_production/packages/NetworkHealth/src", :NetworkHealth),
    ("../vol5_ml_production/packages/TemporalHealth/src", :TemporalHealth),
]
    full_path = joinpath(@__DIR__, pkg_path, "$(mod_name).jl")
    if isfile(full_path)
        try
            include(full_path)
            push!(MODULES, eval(mod_name))
            push!(MODULES_NAMES, String(mod_name) => mod_name)
            @info "Loaded $mod_name"
        catch e
            @warn "Could not load $mod_name: $e"
        end
    end
end

# ── Page tree ──────────────────────────────────────────────────────────────────

PAGES = [
    "Home" => "index.md",
    "Volume 1: Core Geospatial" => [
        "Introduction" => "vol1/index.md",
        "Census Data API" => "vol1/census.md",
        "Geocoding" => "vol1/geocoding.md",
        "E2SFCA Access" => "vol1/e2sfca.md",
        "Choropleth Maps" => "vol1/visualization.md",
    ],
    "Volume 2: Extended Analysis" => [
        "Introduction" => "vol2/index.md",
        "Multi-State Analysis" => "vol2/multistate.md",
        "Advanced Access Methods" => "vol2/advanced_access.md",
    ],
    "Volume 3: Package Ecosystem" => [
        "SpatialStats.jl" => "vol3/spatialstats.md",
        "Geocode.jl" => "vol3/geocode.md",
        "MapClassify.jl" => "vol3/mapclassify.md",
        "Overpass.jl" => "vol3/overpass.md",
    ],
    "Volume 4: Healthcare Platform" => [
        "PointPatterns.jl" => "vol4/pointpatterns.md",
        "Spatial GLMs" => "vol4/spatial_glm.md",
        "Advanced Cartography" => "vol4/cartography.md",
        "North Dakota Pipeline" => "vol4/nd_pipeline.md",
        "Pluto Dashboard" => "vol4/dashboard.md",
        "Genie REST API" => "vol4/api.md",
        "GPU Acceleration" => "vol4/gpu.md",
    ],
    "Volume 5: ML & Production" => [
        "HealthcareML.jl" => "vol5/healthcareml.md",
        "NetworkHealth.jl" => "vol5/networkhealth.md",
        "TemporalHealth.jl" => "vol5/temporalhealth.md",
        "Federated Learning" => "vol5/federated.md",
        "Database Integration" => "vol5/database.md",
        "Real-time Dashboard" => "vol5/realtime.md",
        "Quarto Reports" => "vol5/reports.md",
    ],
    "API Reference" => [
        "All Modules" => "api/index.md",
    ],
]

# ── Build ──────────────────────────────────────────────────────────────────────

makedocs(
    sitename   = "Julia Healthcare GIS — Open Textbook",
    authors    = "Timothy Hartzog",
    modules    = MODULES,
    pages      = PAGES,
    format     = Documenter.HTML(
        prettyurls  = get(ENV, "CI", nothing) == "true",
        canonical   = "https://timothyhartzog.github.io/geo-julia",
        assets      = ["assets/custom.css"],
    ),
    checkdocs  = :exports,
    doctest    = false,  # doctests run separately in CI
)

deploydocs(
    repo = "github.com/timothyhartzog/geo-julia.git",
    devbranch = "main",
    push_preview = true,
)
