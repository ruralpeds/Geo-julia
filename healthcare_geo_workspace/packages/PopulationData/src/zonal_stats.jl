# src/zonal_stats.jl
# Zonal statistics: population sum/mean/max per polygon from a raster.

using DataFrames

"""
    pop_by_polygon(raster_path, polygons_df; stat=sum, missingval=-9999.0f0)
        -> Vector{Float64}

Compute population totals (or another statistic) within each polygon in
`polygons_df` by masking a population raster.

**Requirements:**
- `Rasters.jl` must be installed (loaded lazily at call time)
- `polygons_df` must have a `:geometry` column

`stat` can be `sum` (default, for population totals), `mean`, `maximum`, etc.

Returns a `Vector{Float64}` with one value per row of `polygons_df`.
Values are 0.0 for polygons that contain no valid raster cells.
"""
function pop_by_polygon(raster_path::AbstractString,
                         polygons_df::DataFrame;
                         stat::Function    = sum,
                         missingval::Float32 = -9999.0f0)::Vector{Float64}
    Rasters = Base.require(Base.PkgId(
        Base.UUID("700a0f68-0e07-4f34-ffe2-9db9f3c31d29"), "Rasters"))

    rast    = Rasters.Raster(raster_path; missingval = missingval)
    results = Float64[]

    for row in eachrow(polygons_df)
        val = try
            masked = Rasters.mask(rast; with = row.geometry)
            vals   = filter(v -> !ismissing(v) && !isnan(v) && v != missingval,
                            Float64.(vec(masked)))
            isempty(vals) ? 0.0 : stat(vals)
        catch
            0.0
        end
        push!(results, val)
    end

    return results
end
