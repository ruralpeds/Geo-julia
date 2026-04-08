# src/autocorrelation/lisa.jl
# LISA (Local Indicators of Spatial Association) with cluster mapping.

using Statistics, LinearAlgebra, Random

# ──────────────────────────────────────────────────────────────────────────────
# Result type
# ──────────────────────────────────────────────────────────────────────────────

"""
    LISAResult

Container for a LISA analysis result.

Fields:
- `I_local`      — Local Moran's I value per spatial unit
- `p_values`     — permutation-based p-value per unit
- `cluster_type` — `:HH`, `:LL`, `:HL`, `:LH`, or `:NS` per unit
- `significance` — α threshold used for cluster classification
"""
struct LISAResult
    I_local::Vector{Float64}
    p_values::Vector{Float64}
    cluster_type::Vector{Symbol}
    significance::Float64
end

function Base.show(io::IO, r::LISAResult)
    counts = Dict(t => sum(r.cluster_type .== t)
                  for t in [:HH, :LL, :HL, :LH, :NS])
    println(io, "LISAResult (n=$(length(r.I_local)), α=$(r.significance))")
    for t in [:HH, :LL, :HL, :LH, :NS]
        println(io, "  $(t): $(counts[t])")
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# Core implementation
# ──────────────────────────────────────────────────────────────────────────────

"""
    lisa(y, w::SpatialWeights; permutations=999, alpha=0.05) -> LISAResult

Compute Local Indicators of Spatial Association (Anselin 1995).

The permutation test at each location randomly reassigns values to all *other*
locations (leaving location *i* fixed), consistent with the conditional-randomisation
approach in PySAL's esda.moran.Moran_Local.

Cluster classification:
- **HH** — high value surrounded by high values (hot spot)
- **LL** — low value surrounded by low values (cold spot)
- **HL** — high value surrounded by low values (spatial outlier)
- **LH** — low value surrounded by high values (spatial outlier)
- **NS** — not significant at level `alpha`
"""
function lisa(y::Vector{Float64}, w::SpatialWeights;
              permutations::Int   = 999,
              alpha::Float64      = 0.05)::LISAResult
    n     = length(y)
    W     = Matrix{Float64}(w.W)
    xbar  = mean(y)
    z     = y .- xbar
    s2    = sum(z .^ 2) / n

    Wz      = W * z
    I_local = s2 > 0 ? (z ./ s2) .* Wz : zeros(n)

    # Permutation test — conditional randomisation (fix location i, permute others)
    p_values  = ones(Float64, n)
    others    = copy(z)

    for i in 1:n
        perm_I = Vector{Float64}(undef, permutations)
        idx    = [k for k in 1:n if k != i]   # all locations except i
        for k in 1:permutations
            shuffle!(@view others[idx])
            # Local I at i using permuted neighbours
            lag_i    = dot(W[i, :], others)
            perm_I[k] = s2 > 0 ? (z[i] / s2) * lag_i : 0.0
        end
        copy!(others, z)  # restore
        p_values[i] = mean(abs.(perm_I) .>= abs(I_local[i]))
    end

    # Cluster classification
    cluster_type = Vector{Symbol}(undef, n)
    lag_y        = W * y

    for i in 1:n
        if p_values[i] >= alpha
            cluster_type[i] = :NS
        elseif y[i] >= xbar && lag_y[i] >= xbar
            cluster_type[i] = :HH
        elseif y[i] < xbar && lag_y[i] < xbar
            cluster_type[i] = :LL
        elseif y[i] >= xbar && lag_y[i] < xbar
            cluster_type[i] = :HL
        else
            cluster_type[i] = :LH
        end
    end

    LISAResult(I_local, p_values, cluster_type, alpha)
end

"""
    plot_lisa(result::LISAResult, geoms; title="LISA Cluster Map",
              outfile=nothing) -> Figure

Render a LISA cluster map using GeoMakie/CairoMakie.
"""
function plot_lisa(result::LISAResult, geoms::AbstractVector;
                   title::AbstractString = "LISA Cluster Map",
                   outfile::Union{Nothing, AbstractString} = nothing)
    # Lazy-load plotting dependencies
    GeoMakie  = Base.require(Base.PkgId(
        Base.UUID("db073c08-6b98-4ee5-b22a-4b16714a7f43"), "GeoMakie"))
    CairoMakie = Base.require(Base.PkgId(
        Base.UUID("13f3f980-e62b-5c42-98c6-ff1f3baf88f0"), "CairoMakie"))

    color_map = Dict(:HH => 4.0, :HL => 3.0, :LH => 2.0, :LL => 1.0, :NS => 0.0)
    cvals     = Float64.([get(color_map, c, 0.0) for c in result.cluster_type])

    fig = CairoMakie.Figure(resolution = (1000, 700))
    ax  = GeoMakie.GeoAxis(fig[1, 1];
                            dest  = "+proj=laea +lat_0=45 +lon_0=-96 +ellps=WGS84",
                            title = title,
                            titlefont = :bold)

    CairoMakie.poly!(ax, geoms;
                     color       = cvals,
                     colormap    = [:lightgray, :blue, :cyan, :orange, :red],
                     colorrange  = (0, 4),
                     strokecolor = :white,
                     strokewidth = 0.4)

    legend_items = [CairoMakie.PolyElement(color = c)
                    for c in [:lightgray, :blue, :cyan, :orange, :red]]
    CairoMakie.Legend(fig[1, 2], legend_items,
                      ["NS", "LL (cold)", "LH", "HL", "HH (hot)"];
                      framevisible = false, labelsize = 11)

    if !isnothing(outfile)
        CairoMakie.save(outfile, fig)
        @info "Saved LISA map to $outfile"
    end

    fig
end
