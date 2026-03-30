"""
    HealthcareGeo

A geospatial health analysis library for studying rural population health
and healthcare access disparities. Implements the methods described in
*Geographic Analysis in Julia: Healthcare, Rural Populations, and Spatial
Data Science* (2026 Edition).
"""
module HealthcareGeo

using DataFrames, CSV, Statistics, LinearAlgebra
using Shapefile, ArchGDAL, GeoDataFrames, GeoInterface
using GeoMakie, CairoMakie
using HTTP, JSON
using Dates

# Data sub-modules
include("data/download.jl")
include("data/classify.jl")
include("data/geocoding.jl")
include("data/routing.jl")

# Analysis sub-modules
include("analysis/weights.jl")
include("analysis/autocorrelation.jl")
include("analysis/accessibility.jl")
include("analysis/regression.jl")

# Visualization sub-modules
include("viz/choropleth.jl")

# ──────────────────────────────────────────────────────────────────────────────
# Re-export public API
# ──────────────────────────────────────────────────────────────────────────────

export
    # data/download.jl
    download_tiger_counties,
    download_ruca_codes,
    download_hpsa_shapefile,
    fetch_acs_insurance_coverage,
    load_ahrf,

    # data/classify.jl
    classify_rural_forhp,

    # data/geocoding.jl
    census_geocode_batch,
    geocode_all,

    # data/routing.jl
    osrm_table,
    osrm_route,
    download_osm_network,

    # analysis/weights.jl
    build_queen_weights,
    build_knn_weights,
    build_distance_band_weights,
    build_inverse_distance_weights,

    # analysis/autocorrelation.jl
    compute_morans_i,
    compute_geary_c,
    lisa_clusters,
    getis_ord_g,

    # analysis/accessibility.jl
    haversine,
    two_step_fca,
    e2sfca,
    network_2sfca,
    gravity_accessibility,

    # analysis/regression.jl
    spatial_lag_model,
    spatial_error_model,
    gwr,

    # viz/choropleth.jl
    make_choropleth_map,
    healthcare_atlas,

    # high-level loaders (convenience wrappers defined below)
    load_counties,
    load_providers

# ──────────────────────────────────────────────────────────────────────────────
# High-level convenience loaders
# ──────────────────────────────────────────────────────────────────────────────

"""
    load_counties(shp_path) -> DataFrame

Load a county TIGER/Line shapefile into a GeoDataFrame.
Returns a DataFrame with geometry column and all TIGER attributes.
"""
function load_counties(shp_path::AbstractString)::DataFrame
    GeoDataFrames.read(shp_path)
end

"""
    load_providers(csv_path) -> DataFrame

Load a provider CSV file.  Expected columns: name, lat, lon, supply
(where supply is typically FTE count or number of physicians).
"""
function load_providers(csv_path::AbstractString)::DataFrame
    CSV.read(csv_path, DataFrame)
end

end  # module HealthcareGeo
