#!/usr/bin/env julia
# dashboard/realtime_app.jl
# Real-time healthcare access dashboard with WebSocket live updates
# Chapter 40 — Julia Healthcare GIS Textbook, Vol 5
#
# Architecture:
#   - Genie.jl HTTP server (REST + WebSocket)
#   - Server-sent events (SSE) for live Moran's I updates
#   - Background task recomputes spatial statistics every 30s
#   - In-memory state store (thread-safe with ReentrantLock)
#
# Run: julia --project=. dashboard/realtime_app.jl

using Dates, Statistics, JSON3, Random

# ── State store ───────────────────────────────────────────────────────────────

const STATE_LOCK = ReentrantLock()

mutable struct DashboardState
    access_scores   ::Vector{Float64}
    moran_i         ::Float64
    moran_p         ::Float64
    lisa_clusters   ::Vector{String}
    last_updated    ::DateTime
    catchment_km    ::Float64
    n_counties      ::Int
    update_count    ::Int
    sse_clients     ::Vector{Channel{String}}
end

const GLOBAL_STATE = DashboardState(
    Float64[], NaN, NaN, String[],
    now(), 50.0, 53, 0, Channel{String}[]
)

function update_state!(f::Function)
    lock(STATE_LOCK) do
        f(GLOBAL_STATE)
        GLOBAL_STATE.last_updated = now()
        GLOBAL_STATE.update_count += 1
    end
end

function get_state_snapshot()
    lock(STATE_LOCK) do
        (
            access_scores  = copy(GLOBAL_STATE.access_scores),
            moran_i        = GLOBAL_STATE.moran_i,
            moran_p        = GLOBAL_STATE.moran_p,
            lisa_clusters  = copy(GLOBAL_STATE.lisa_clusters),
            last_updated   = GLOBAL_STATE.last_updated,
            catchment_km   = GLOBAL_STATE.catchment_km,
            n_counties     = GLOBAL_STATE.n_counties,
            update_count   = GLOBAL_STATE.update_count,
        )
    end
end

# ── Synthetic spatial analysis (CPU fallback) ──────────────────────────────────

function _recompute_analysis!(state, catchment_km)
    n     = state.n_counties
    rng   = MersenneTwister(state.update_count)

    # Simulate access scores that drift over time
    base  = abs.(randn(rng, n)) .* 0.01 .+ 0.003
    noise = 0.001 .* randn(rng, n)
    scores = base .+ noise

    # Toy Moran's I (chain weights)
    n_pairs = n - 1
    spatial_lag = [j == 1 ? scores[j+1] :
                   j == n ? scores[j-1] :
                   (scores[j-1] + scores[j+1]) / 2 for j in 1:n]
    z   = (scores .- mean(scores)) ./ max(std(scores), 1e-9)
    wz  = (spatial_lag .- mean(spatial_lag)) ./ max(std(spatial_lag), 1e-9)
    I   = dot(z, wz) / (n - 1)

    # Simple permutation p-value (99 permutations)
    perm_I = [begin
        zp = z[randperm(rng, n)]
        dot(zp, wz) / (n-1)
    end for _ in 1:99]
    p_val = (sum(perm_I .>= I) + 1) / 100

    # LISA (simplified: only HH/LL based on sign)
    clusters = [z[j] > 0 && wz[j] > 0 ? "HH" :
                z[j] < 0 && wz[j] < 0 ? "LL" :
                z[j] > 0 && wz[j] < 0 ? "HL" :
                z[j] < 0 && wz[j] > 0 ? "LH" : "NS"
                for j in 1:n]

    state.access_scores = scores
    state.moran_i       = I
    state.moran_p       = p_val
    state.lisa_clusters = clusters
    state.catchment_km  = catchment_km
end

# ── SSE broadcast ─────────────────────────────────────────────────────────────

function broadcast_update!(msg::String)
    lock(STATE_LOCK) do
        dead = Int[]
        for (i, ch) in enumerate(GLOBAL_STATE.sse_clients)
            try
                isopen(ch) ? put!(ch, msg) : push!(dead, i)
            catch
                push!(dead, i)
            end
        end
        for i in reverse(dead)
            deleteat!(GLOBAL_STATE.sse_clients, i)
        end
    end
end

# ── Background update task ─────────────────────────────────────────────────────

const UPDATE_INTERVAL_S = 30

function start_background_updater!()
    @async while true
        try
            update_state!() do state
                _recompute_analysis!(state, state.catchment_km)
            end
            snap = get_state_snapshot()
            msg  = JSON3.write(Dict(
                "type"         => "update",
                "moran_i"      => snap.moran_i,
                "moran_p"      => snap.moran_p,
                "last_updated" => string(snap.last_updated),
                "update_count" => snap.update_count,
                "hh_count"     => count(==("HH"), snap.lisa_clusters),
                "ll_count"     => count(==("LL"), snap.lisa_clusters),
            ))
            broadcast_update!(msg)
            @info "Analysis updated: Moran I=$(round(snap.moran_i; digits=4)), " *
                  "p=$(round(snap.moran_p; digits=3)) [update #$(snap.update_count)]"
        catch e
            @warn "Background update error: $e"
        end
        sleep(UPDATE_INTERVAL_S)
    end
end

# ── Genie.jl app (optional) ────────────────────────────────────────────────────

const GENIE_AVAILABLE = try
    @eval using Genie, Genie.Router, Genie.Renderer.Json
    true
catch
    false
end

function setup_routes!()
    !GENIE_AVAILABLE && return

    Genie.Router.route("/api/v2/health") do
        snap = get_state_snapshot()
        Json.json(Dict("status"=>"ok", "update_count"=>snap.update_count,
                       "last_updated"=>string(snap.last_updated)))
    end

    Genie.Router.route("/api/v2/state") do
        snap = get_state_snapshot()
        Json.json(Dict(
            "moran_i"       => snap.moran_i,
            "moran_p"       => snap.moran_p,
            "catchment_km"  => snap.catchment_km,
            "last_updated"  => string(snap.last_updated),
            "update_count"  => snap.update_count,
            "access_mean"   => isempty(snap.access_scores) ? NaN : mean(snap.access_scores),
            "access_std"    => isempty(snap.access_scores) ? NaN : std(snap.access_scores),
            "hh_counties"   => count(==("HH"), snap.lisa_clusters),
            "ll_counties"   => count(==("LL"), snap.lisa_clusters),
        ))
    end

    Genie.Router.route("/api/v2/catchment/:km") do
        km = parse(Float64, Genie.Router.params(:km))
        km = clamp(km, 5.0, 200.0)
        update_state!() do state
            state.catchment_km = km
            _recompute_analysis!(state, km)
        end
        snap = get_state_snapshot()
        Json.json(Dict("catchment_km"=>km, "moran_i"=>snap.moran_i,
                       "access_mean"=>mean(snap.access_scores)))
    end

    # SSE endpoint for real-time updates
    Genie.Router.route("/api/v2/events") do
        ch = Channel{String}(32)
        lock(STATE_LOCK) do
            push!(GLOBAL_STATE.sse_clients, ch)
        end
        # SSE headers
        Genie.Renderer.respond(
            "text/event-stream",
            ["Cache-Control"=>"no-cache", "X-Accel-Buffering"=>"no"],
        ) do
            # Send initial state
            snap = get_state_snapshot()
            yield("data: " * JSON3.write(Dict("type"=>"init",
                                               "moran_i"=>snap.moran_i)) * "\n\n")
            # Stream updates
            for msg in ch
                yield("data: $msg\n\n")
            end
        end
    end
end

# ── Main ──────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__
    @info "Healthcare Real-time Dashboard — Chapter 40"
    @info "WebSocket/SSE live Moran's I updates every $(UPDATE_INTERVAL_S)s"

    # Initial computation
    update_state!() do state
        _recompute_analysis!(state, state.catchment_km)
    end

    snap = get_state_snapshot()
    @info "Initial analysis: Moran I=$(round(snap.moran_i; digits=4)), " *
          "p=$(round(snap.moran_p; digits=3))"
    @info "LISA clusters: HH=$(count(==("HH"), snap.lisa_clusters)), " *
          "LL=$(count(==("LL"), snap.lisa_clusters)), " *
          "HL=$(count(==("HL"), snap.lisa_clusters)), " *
          "LH=$(count(==("LH"), snap.lisa_clusters))"

    # Start background updater
    start_background_updater!()

    if GENIE_AVAILABLE
        setup_routes!()
        @info "Starting Genie.jl server on port 8081..."
        Genie.startup(8081; async=false)
    else
        @warn "Genie.jl not available. Running background updater only."
        @info "Press Ctrl+C to stop. Updating every $(UPDATE_INTERVAL_S)s..."
        while true
            sleep(UPDATE_INTERVAL_S + 1)
        end
    end
end
