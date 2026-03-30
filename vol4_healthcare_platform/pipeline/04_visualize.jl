#!/usr/bin/env julia
# pipeline/04_visualize.jl
# North Dakota Analysis — Visualization Layer
# Creates: 4-panel atlas, bivariate access×poverty map, county-level reports
# Vol 4 — Chapter 29.1.4

include("03_spatial_analysis.jl")

# Visualization requires CairoMakie + GeoMakie — graceful fallback
const VIZ_AVAILABLE = try
    using CairoMakie, GeoMakie, ColorSchemes
    true
catch
    @warn "CairoMakie/GeoMakie not available. Visualization skipped."
    false
end

const ND_PROJ = "+proj=laea +lat_0=47 +lon_0=-100 +ellps=WGS84"

"""
    _quantile_classify(v, k) -> Vector{Int}

Classify vector v into k quantile classes.
"""
_quantile_classify(v, k) = let q = quantile(v, range(0, 1; length=k+1))
    [min(searchsortedfirst(q, x), k) for x in v]
end

"""
    create_atlas(nd_df, analysis_results; outfile="nd_healthcare_atlas.pdf")

Generate the North Dakota healthcare atlas: 4-panel figure.
Panels: E2SFCA access, LISA clusters, poverty rate, bivariate (access×poverty).
"""
function create_atlas(nd_df, ar; outfile=joinpath(PROC_DIR, "nd_healthcare_atlas.pdf"))
    VIZ_AVAILABLE || (@warn "Skipping atlas: visualization not available"; return nothing)
    hasproperty(nd_df, :geometry) && !isnothing(nd_df.geometry[1]) ||
        (@warn "Skipping atlas: no geometry column"; return nothing)

    fig = Figure(resolution=(1800, 1200), fontsize=13, backgroundcolor=:white)

    Label(fig[0, 1:4],
          "North Dakota Primary Care Access Analysis",
          fontsize=22, font=:bold, tellwidth=false)

    # ── Panel 1: E2SFCA Access Scores ─────────────────────────────────────
    ax1 = GeoAxis(fig[1,1]; dest=ND_PROJ, title="E2SFCA Access Score")
    access_vals = Float64.(coalesce.(nd_df.access_score, 0.0))
    poly!(ax1, nd_df.geometry;
          color=access_vals, colormap=:YlGn,
          strokecolor=:white, strokewidth=0.4)
    Colorbar(fig[1,2]; colormap=:YlGn, label="Access Score",
             limits=extrema(access_vals), width=15)

    # ── Panel 2: LISA Cluster Map ──────────────────────────────────────────
    ax2 = GeoAxis(fig[1,3]; dest=ND_PROJ, title="LISA Clusters (Access)")
    cluster_colors = Dict(
        :HH => RGBf(0.78, 0.18, 0.18),
        :LL => RGBf(0.21, 0.45, 0.74),
        :HL => RGBf(0.96, 0.62, 0.18),
        :LH => RGBf(0.67, 0.85, 0.91),
        :NS => RGBf(0.92, 0.92, 0.92),
    )
    colors_lisa = [cluster_colors[c] for c in nd_df.lisa_cluster]
    poly!(ax2, nd_df.geometry; color=colors_lisa,
          strokecolor=:white, strokewidth=0.4)

    # ── Panel 3: Poverty Rate ──────────────────────────────────────────────
    ax3 = GeoAxis(fig[2,1]; dest=ND_PROJ, title="Poverty Rate (%)")
    pov_vals = Float64.(coalesce.(nd_df.poverty_pct,
                                   median(skipmissing(nd_df.poverty_pct))))
    poly!(ax3, nd_df.geometry;
          color=pov_vals, colormap=:Oranges,
          strokecolor=:white, strokewidth=0.4)
    Colorbar(fig[2,2]; colormap=:Oranges, label="Poverty %",
             limits=extrema(pov_vals), width=15)

    # ── Panel 4: Bivariate Map — Access × Poverty ─────────────────────────
    ax4 = GeoAxis(fig[2,3]; dest=ND_PROJ, title="Bivariate: Access × Poverty")
    c1  = _quantile_classify(access_vals, 3)
    c2  = _quantile_classify(pov_vals, 3)
    pal = ["#e8e8e8" "#ace4e4" "#5ac8c8";
           "#dfb0d6" "#a5add3" "#5698b9";
           "#be64ac" "#8c62aa" "#3b4994"]
    biv_colors = [parse(RGBf, pal[c1[i], c2[i]]) for i in 1:nrow(nd_df)]
    poly!(ax4, nd_df.geometry;
          color=biv_colors, strokecolor=:white, strokewidth=0.4)

    save(outfile, fig; pt_per_unit=1)
    @info "Atlas saved: $(outfile)"
    fig
end

"""
    create_pointpattern_plot(analysis_results; outfile)

Plot K-function with CSR envelope for access score spatial pattern.
"""
function create_pointpattern_plot(ar; outfile=joinpath(PROC_DIR, "kfunction.pdf"))
    VIZ_AVAILABLE || return nothing

    using PointPatterns
    nd_df = ar.nd_df
    n = nrow(nd_df)

    # Build PointPattern from county centroids
    w_box = RectWindow(
        minimum(nd_df.centroid_lon) - 1,
        maximum(nd_df.centroid_lon) + 1,
        minimum(nd_df.centroid_lat) - 1,
        maximum(nd_df.centroid_lat) + 1,
    )
    pp = PointPattern(nd_df.centroid_lon, nd_df.centroid_lat, w_box)

    env = envelope(pp, Kfunction; nsim=49)

    fig = Figure(resolution=(800, 500))
    ax  = Axis(fig[1,1]; xlabel="Distance (degrees)", ylabel="K(r)",
               title="Ripley's K-function: ND County Centroids (n=$(n))")

    band!(ax, env.r, env.K_lo, env.K_hi; color=(:grey, 0.3), label="95% CSR envelope")
    lines!(ax, env.r, env.K_csr;  color=:black,  linestyle=:dash, label="CSR theoretical")
    lines!(ax, env.r, env.K_obs;  color=:blue,   linewidth=2,     label="Observed K(r)")
    axislegend(ax)

    save(outfile, fig)
    @info "K-function plot saved: $(outfile)"
    fig
end

# ── Run Phase 4 ───────────────────────────────────────────────────────────────
create_atlas(analysis_results.nd_df, analysis_results)
@info "Phase 4 (visualization) complete."
