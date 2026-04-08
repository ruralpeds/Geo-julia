# CLAUDE CODE SPECIFICATION: PopulationData.jl
# File: specs/12_population_data_package.md
# Vol 2 Chapter 13.5

## Task
Implement PopulationData.jl — a unified Julia client for global and U.S.
population datasets used in rural health geographic analysis.

## Package Structure
```
packages/PopulationData/
├── Project.toml
└── src/
    ├── PopulationData.jl   # main module
    ├── worldpop.jl         # WorldPop raster download
    ├── ghsl.jl             # GHSL raster download
    ├── landscan.jl         # LandScan guidance
    ├── census_client.jl    # ACS API client
    └── zonal_stats.jl      # Rasters.jl zonal statistics
```

## Functions to Implement

### download_worldpop(country_iso3, year; resolution="1km", force_refresh=false)
Download WorldPop constrained, UN-adjusted population raster.
URL: https://data.worldpop.org/GIS/Population/Global_2000_2020/{year}/{ISO3}/
Cache in ~/.julia_geodata/population/worldpop/.

### download_ghsl(year; resolution=100, force_refresh=false)
Download GHSL GHS-POP R2023A raster.
Valid years: 1975, 1980, 1985, 1990, 1995, 2000, 2005, 2010, 2015, 2020, 2025, 2030
Resolution: 100m or 1000m
Cache in ~/.julia_geodata/population/ghsl/.

### get_acs(variables; geography, state, county, year, api_key)
Fetch ACS 5-year estimates from Census API.
Return DataFrame with geoid, variable columns, and geographic identifiers.
Support geographies: "county", "tract", "state", "block group".

### get_acs_variables(year; search)
Return full ACS variable catalog, optionally filtered by keyword.

### pop_by_polygon(raster_path, polygons_df; stat=sum)
Zonal statistics using Rasters.jl mask approach.
Return Vector{Float64} with one value per polygon row.

## Caching Strategy
Use ~/.julia_geodata/population/ as the root cache directory.
Files are cached indefinitely (population rasters don't change).
force_refresh=true forces re-download.

## Error Handling
All download functions must:
- Provide informative error messages with the attempted URL
- Validate filesize > 0 after download
- Handle HTTP 4xx/5xx errors gracefully
