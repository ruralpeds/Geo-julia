# src/viz/choropleth.jl
# Choropleth mapping and multi-panel healthcare atlas using GeoMakie/CairoMakie.

using GeoMakie, CairoMakie

# ──────────────────────────────────────────────────────────────────────────────
# Single-variable choropleth
# ──────────────────────────────────────────────────────────────────────────────

"""
    make_choropleth_map(geoms, values, title;
                        colormap=:Reds,
                        projection="+proj=laea +lat_0=45 +lon_0=-96 +ellps=WGS84",
                        outfile=nothing) -> Figure

Render a single-variable choropleth map.

- `geoms`      — vector of polygon geometries (GeoInterface-compatible)
- `values`     — numeric vector of the same length
- `title`      — map title string
- `colormap`   — any Makie-compatible color map symbol or name
- `projection` — PROJ string for the map projection
- `outfile`    — if provided, save the figure to this path (PDF/PNG/SVG)
"""
function make_choropleth_map(geoms::AbstractVector,
                               values::AbstractVector,
                               title::AbstractString;
                               colormap::Union{Symbol, AbstractString} = :Reds,
                               projection::AbstractString =
                                   "+proj=laea +lat_0=45 +lon_0=-96 +ellps=WGS84",
                               outfile::Union{Nothing, AbstractString} = nothing)::Figure
    fig = Figure(resolution = (1200, 800), fontsize = 13)
    ga  = GeoAxis(fig[1, 1];
                  dest            = projection,
                  title           = title,
                  titlefont       = :bold,
                  backgroundcolor = "#F5F5F5")

    vmin, vmax = extrema(values)
    poly!(ga, geoms;
          color       = values,
          colormap    = colormap,
          colorrange  = (vmin, vmax),
          strokecolor = :white,
          strokewidth = 0.3)

    Colorbar(fig[1, 2];
             colormap = colormap,
             limits   = (vmin, vmax),
             label    = title,
             width    = 15,
             height   = Relative(0.7))

    if !isnothing(outfile)
        save(outfile, fig; pt_per_unit = 1)
        @info "Saved map to $(outfile)"
    end

    return fig
end

# ──────────────────────────────────────────────────────────────────────────────
# Four-panel healthcare atlas
# ──────────────────────────────────────────────────────────────────────────────

"""
    healthcare_atlas(counties_df, county_geoms;
                     outfile="healthcare_atlas.pdf")

Create a four-panel healthcare atlas map:
1. Primary care provider density (providers per 100 k population)
2. HPSA designation score
3. E2SFCA spatial accessibility score
4. LISA clusters of cardiovascular mortality

`counties_df` must contain columns:
`:provider_per_100k`, `:hpsa_score`, `:access_2sfca`, `:lisa_cluster`

The function saves to `outfile` and returns the `Figure`.
"""
function healthcare_atlas(counties_df::DataFrame,
                            county_geoms::AbstractVector;
                            outfile::AbstractString = "healthcare_atlas.pdf")::Figure
    proj = "+proj=laea +lat_0=45 +lon_0=-96 +ellps=WGS84"

    fig = Figure(resolution = (1800, 1200), fontsize = 14)
    fig[0, 1:4] = Label(fig,
                         "Rural Healthcare Access Atlas",
                         fontsize  = 22,
                         font      = :bold,
                         tellwidth = false)

    panels = [
        (1, 1, :provider_per_100k, "Primary Care MDs per 100 k",   :YlGn),
        (1, 3, :hpsa_score,        "HPSA Designation Score",        :Reds),
        (2, 1, :access_2sfca,      "E2SFCA Accessibility Score",    :Blues),
        (2, 3, :lisa_cluster,      "CVD Mortality LISA Clusters",   :RdBu),
    ]

    for (row, col, var, title, cmap) in panels
        ax = GeoAxis(fig[row, col];
                     dest            = proj,
                     title           = title,
                     titlefont       = :bold,
                     backgroundcolor = "#F5F5F5")

        vals = counties_df[!, var]
        poly!(ax, county_geoms;
              color       = vals,
              colormap    = cmap,
              strokecolor = :white,
              strokewidth = 0.3)

        Colorbar(fig[row, col + 1];
                 colormap = cmap,
                 limits   = (minimum(vals), maximum(vals)),
                 label    = title,
                 width    = 15,
                 height   = Relative(0.7))
    end

    save(outfile, fig; pt_per_unit = 1)
    @info "Saved atlas to $(outfile)"
    return fig
end
