"""
    PopulationData

Unified population data access for Julia.  Provides download clients for:
- **WorldPop** — 1 km and 100 m constrained population rasters (2000–2020)
- **GHSL** — Global Human Settlement Layer population (1975–2030)
- **LandScan** — Oak Ridge National Laboratory ambient population
- **Kontur** — H3 hexagon population dataset
- **U.S. Census ACS** — tract/county/state estimates via REST API

All rasters are cached in `~/.julia_geodata/population/` by default.
"""
module PopulationData

using HTTP, JSON, CSV, DataFrames, Dates

include("worldpop.jl")
include("ghsl.jl")
include("landscan.jl")
include("census_client.jl")
include("zonal_stats.jl")

export
    # WorldPop
    download_worldpop,
    # GHSL
    download_ghsl,
    # LandScan
    landscan_info,
    # Census ACS
    get_acs,
    get_acs_variables,
    # Zonal stats
    pop_by_polygon,
    # Cache management
    DATA_DIR,
    clear_cache

const DATA_DIR = joinpath(homedir(), ".julia_geodata", "population")

"""
    clear_cache(; subdir=nothing)

Delete cached population data files.  Pass `subdir` (e.g. `"worldpop"`) to
clear only that source; omit to clear everything.
"""
function clear_cache(; subdir::Union{Nothing, String} = nothing)
    target = isnothing(subdir) ? DATA_DIR : joinpath(DATA_DIR, subdir)
    if isdir(target)
        rm(target; recursive = true)
        @info "Cleared cache: $target"
    end
end

end  # module PopulationData
