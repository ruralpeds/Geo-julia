#!/usr/bin/env julia
# web/app.jl — Genie.jl REST API for Healthcare GIS
# Exposes spatial analysis as HTTP endpoints.
# Run: julia --project=. web/app.jl
# Vol 4 — Chapter 31.1

using Genie, Genie.Router, Genie.Renderer.Json, Genie.Requests
using DataFrames, CSV, JSON3, Serialization
using SparseArrays, Statistics

# Load spatial analysis packages
using SpatialStats

# ── Pre-load analysis data at startup ─────────────────────────────────────────
const ND_DATA = Ref{NamedTuple}()
const DATA_DIR = joinpath(@__DIR__, "..", "data", "processed")

function _build_weights_from_csv(nd_df::DataFrame)
    n = nrow(nd_df)
    Is = Int[]; Js = Int[]; Vs = Float64[]
    for i in 1:n-1
        push!(Is, i, i+1); push!(Js, i+1, i); push!(Vs, 1.0, 1.0)
    end
    for i in 1:n-8
        push!(Is, i, i+8); push!(Js, i+8, i); push!(Vs, 1.0, 1.0)
    end
    W = sparse(Is, Js, Vs, n, n)
    row_sums = vec(sum(W; dims=2))
    rows, cols, vals = findnz(W)
    for k in eachindex(rows); vals[k] /= row_sums[rows[k]]; end
    W = sparse(rows, cols, vals, n, n)
    SpatialStats.SpatialWeights(W, n,
        SpatialStats.RowStandardizedStyle(), SpatialStats.QueenTransform(),
        0, mean(vec(sum(W .!= 0; dims=2))), 1, 8)
end

function __init_analysis__()
    @info "Loading North Dakota analysis data..."
    nd_df = try
        CSV.read(joinpath(DATA_DIR, "nd_analysis_results.csv"), DataFrame)
    catch
        @warn "Analysis results not found. Using synthetic demo data."
        n = 53
        DataFrame(
            GEOID         = ["38" * lpad(i, 3, '0') for i in 1:n],
            NAME          = ["County $(i)" for i in 1:n],
            centroid_lat  = 46.5 .+ range(-2.0, 2.0; length=n),
            centroid_lon  = -100.5 .+ range(-3.0, 3.0; length=n),
            access_score  = abs.(randn(n)) .* 0.01 .+ 0.005,
            poverty_pct   = 5.0  .+ 15.0 .* rand(n),
            uninsured_pct = 8.0  .+ 12.0 .* rand(n),
            total_pop     = 1000 .+ round.(Int, 50000 .* rand(n).^2),
            lisa_cluster  = rand(["HH","LL","HL","LH","NS"], n),
        )
    end

    w = if isfile(joinpath(DATA_DIR, "nd_weights.jls"))
        deserialize(joinpath(DATA_DIR, "nd_weights.jls"))
    else
        @info "Building synthetic weights..."
        _build_weights_from_csv(nd_df)
    end

    ND_DATA[] = (; nd_df, w)
    @info "Analysis data loaded: $(nrow(nd_df)) counties"
end

# ── API Routes ────────────────────────────────────────────────────────────────

# GET /api/health — health check
route("/api/health") do
    json(Dict("status" => "ok", "counties" => nrow(ND_DATA[].nd_df)))
end

# GET /api/counties — list all county summaries
route("/api/counties") do
    df = ND_DATA[].nd_df
    result = [(
        geoid         = r.GEOID,
        name          = r.NAME,
        access_score  = coalesce(r.access_score, 0.0),
        lisa_cluster  = string(coalesce(r.lisa_cluster, "NS")),
        poverty_pct   = coalesce(r.poverty_pct, 0.0),
        uninsured_pct = coalesce(r.uninsured_pct, 0.0),
        total_pop     = coalesce(r.total_pop, 0),
    ) for r in eachrow(df)]
    json(result)
end

# GET /api/county/:geoid — single county detail
route("/api/county/:geoid") do
    geoid = params(:geoid)
    df    = ND_DATA[].nd_df
    w     = ND_DATA[].w
    row   = findfirst(==(geoid), string.(df.GEOID))

    isnothing(row) &&
        return json(Dict("error" => "County $(geoid) not found"); status=404)

    r = df[row, :]

    # Find neighbours
    nb_indices = findnz(w.W[row, :])[1]
    neighbor_names = [string(df.NAME[j]) for j in nb_indices]

    json((
        geoid         = r.GEOID,
        name          = r.NAME,
        access_score  = coalesce(r.access_score, 0.0),
        lisa_cluster  = string(coalesce(r.lisa_cluster, "NS")),
        poverty_pct   = coalesce(r.poverty_pct, 0.0),
        uninsured_pct = coalesce(r.uninsured_pct, 0.0),
        total_pop     = coalesce(r.total_pop, 0),
        neighbors     = neighbor_names,
        centroid      = (lat=r.centroid_lat, lon=r.centroid_lon),
    ))
end

# POST /api/moran — compute Moran's I for custom variable array
route("/api/moran", method=POST) do
    body = jsonpayload()
    haskey(body, "values") || return json(Dict("error" => "Request body must have 'values' key"); status=400)

    vals = try Float64.(body["values"]) catch
        return json(Dict("error" => "values must be numeric"); status=400)
    end

    w = ND_DATA[].w
    length(vals) == w.n ||
        return json(Dict("error" => "Expected $(w.n) values, got $(length(vals))"); status=400)

    r = moran(vals, w; permutations=get(body, "permutations", 999))
    json((
        I        = r.I,
        expected = r.expected_I,
        z_score  = r.z_score,
        p_value  = r.p_value,
        method   = string(r.method),
        interpretation = r.I > 0 && r.p_value < 0.05 ? "Significant positive clustering" :
                         r.I < 0 && r.p_value < 0.05 ? "Significant negative clustering" :
                         "Not significant",
    ))
end

# GET /api/access?catchment=45 — recompute access scores
route("/api/access") do
    catchment_km = parse(Float64, get(params(), :catchment, "45"))
    (1.0 <= catchment_km <= 200.0) ||
        return json(Dict("error" => "catchment must be 1–200 km"); status=400)

    prov_path = joinpath(DATA_DIR, "providers_geocoded.csv")
    prov = if isfile(prov_path)
        CSV.read(prov_path, DataFrame)
    else
        # Demo providers
        DataFrame(lat=randn(30) .* 0.5 .+ 46.8, lon=randn(30) .* 1.0 .+ -100.5)
    end

    df = ND_DATA[].nd_df
    n  = nrow(df)
    σ_km = catchment_km / 3.0
    access = zeros(Float64, n)

    for j in 1:nrow(prov)
        pl = Float64(coalesce(prov.lat[j], 46.5))
        lo = Float64(coalesce(prov.lon[j], -100.5))
        for i in 1:n
            d = haversine_km(pl, lo,
                             Float64(df.centroid_lat[i]),
                             Float64(df.centroid_lon[i]))
            d <= catchment_km &&
                (access[i] += exp(-d^2 / (2σ_km^2)))
        end
    end

    json([(geoid=df.GEOID[i], access_score=access[i]) for i in 1:n])
end

# GET /api/lisa — LISA cluster map
route("/api/lisa") do
    alpha = parse(Float64, get(params(), :alpha, "0.05"))
    (0.001 <= alpha <= 0.20) ||
        return json(Dict("error" => "alpha must be 0.001–0.20"); status=400)

    df = ND_DATA[].nd_df
    w  = ND_DATA[].w

    access_vals = Float64.(coalesce.(df.access_score, 0.0))
    r = lisa(access_vals, w; permutations=499, alpha=alpha)

    json([(geoid=df.GEOID[i], cluster=string(r.cluster_type[i]),
           p_value=r.p_values[i], I_local=r.I_local[i])
          for i in 1:nrow(df)])
end

# ── Start server ──────────────────────────────────────────────────────────────
__init_analysis__()

@info "Starting Healthcare GIS API on port 8080"
@info "Endpoints: GET /api/health, /api/counties, /api/county/:geoid"
@info "           POST /api/moran, GET /api/access?catchment=N, /api/lisa?alpha=N"

Genie.config.run_as_server = true
Genie.startup(port=8080, async=false)
