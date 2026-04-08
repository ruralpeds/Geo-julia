# src/ghsl.jl
# Global Human Settlement Layer (GHSL) population raster downloader.

using HTTP

const GHSL_VALID_YEARS = (1975, 1980, 1985, 1990, 1995, 2000, 2005,
                           2010, 2015, 2020, 2025, 2030)

"""
    download_ghsl(year; resolution=100, force_refresh=false) -> String

Download the Global Human Settlement Layer population raster (GHS-POP R2023A).

- `year`         — one of $(GHSL_VALID_YEARS)
- `resolution`   — `100` (metres, default) or `1000`
- `force_refresh` — re-download even if cached

Returns the local path to the downloaded GeoTIFF.

**Note:** GHSL files are large (>1 GB at 100 m resolution).  Ensure sufficient
disk space and a stable connection.
"""
function download_ghsl(year::Int;
                        resolution::Int  = 100,
                        force_refresh::Bool = false)::String
    year in GHSL_VALID_YEARS || error("Invalid GHSL year: $year. " *
        "Choose from $(GHSL_VALID_YEARS).")
    resolution in (100, 1000) || error("resolution must be 100 or 1000")

    res_str  = resolution == 100 ? "R2023A_4326_100" : "R2023A_4326_1000"
    filename = "GHS_POP_E$(year)_GLOBE_$(res_str)_V1_0.tif"
    dest_dir = mkpath(joinpath(DATA_DIR, "ghsl"))
    dest     = joinpath(dest_dir, filename)

    if !force_refresh && isfile(dest) && filesize(dest) > 0
        @info "Using cached GHSL raster: $dest"
        return dest
    end

    base = "https://jeodpp.jrc.ec.europa.eu/ftp/jrc-opendata/GHSL"
    url  = "$(base)/GHS_POP_GLOBE_R2023A/GHS_POP_E$(year)_GLOBE_$(res_str)_V1_0/V1-0/$(filename)"

    @info "Downloading GHSL $(year) at $(resolution) m — this may be > 1 GB."
    @info "URL: $url"
    try
        resp = HTTP.get(url; readtimeout = 3600, status_exception = true)
        write(dest, resp.body)
        @info "Saved to $dest ($(round(filesize(dest)/1e9; digits=2)) GB)"
    catch e
        error("GHSL download failed.\nURL: $(url)\nError: $(e)")
    end

    return dest
end
