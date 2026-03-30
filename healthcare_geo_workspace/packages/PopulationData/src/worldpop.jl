# src/worldpop.jl
# WorldPop constrained population raster downloader.

using HTTP, Dates

"""
    download_worldpop(country_iso3, year; resolution="1km", force_refresh=false)
        -> String

Download a WorldPop constrained, UN-adjusted population raster.

- `country_iso3` — ISO 3166-1 alpha-3 code (e.g. `"USA"`, `"MEX"`)
- `year`         — 2000–2020 for historical; projections may be available
- `resolution`   — `"1km"` (default) or `"100m"` (only available for 2020)
- `force_refresh` — re-download even if cached

Returns the local path to the downloaded GeoTIFF.

**Cache location:** `~/.julia_geodata/population/worldpop/`

**URL pattern:**
`https://data.worldpop.org/GIS/Population/Global_2000_2020/{year}/{ISO3}/{iso3}_ppp_{year}_{res}_Aggregated_UNadj.tif`
"""
function download_worldpop(country_iso3::AbstractString, year::Int;
                             resolution::AbstractString = "1km",
                             force_refresh::Bool = false)::String
    iso_upper = uppercase(country_iso3)
    iso_lower = lowercase(country_iso3)
    dest_dir  = mkpath(joinpath(DATA_DIR, "worldpop"))
    filename  = "$(iso_lower)_ppp_$(year)_$(resolution)_Aggregated_UNadj.tif"
    dest      = joinpath(dest_dir, filename)

    if !force_refresh && isfile(dest) && filesize(dest) > 0
        @info "Using cached WorldPop raster: $dest"
        return dest
    end

    base = "https://data.worldpop.org/GIS/Population/Global_2000_2020"
    url  = "$(base)/$(year)/$(iso_upper)/$(filename)"

    @info "Downloading WorldPop $(iso_upper) $(year) ($(resolution))…"
    @info "URL: $url"
    try
        resp = HTTP.get(url; readtimeout = 600, status_exception = true)
        write(dest, resp.body)
        @info "Saved to $dest ($(round(filesize(dest)/1e6; digits=1)) MB)"
    catch e
        error("WorldPop download failed.\nURL: $(url)\nError: $(e)")
    end

    return dest
end
