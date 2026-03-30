using Test
using Overpass

# ── OverpassQuery fluent builder ──────────────────────────────────────────────
@testset "OverpassQuery builder" begin
    q = OverpassQuery()
    @test q.bbox     === nothing
    @test q.out_mode == :json
    @test q.recurse  == false

    # Pipe syntax
    q = OverpassQuery() |>
        within_bbox(45.0, -100.0, 47.0, -96.0) |>
        node_with_tag("amenity", "hospital") |>
        recurse_down() |>
        output(:json)

    @test q.bbox == (45.0, -100.0, 47.0, -96.0)
    @test q.recurse == true
    @test q.out_mode == :json
    @test length(q.filters) == 1
    @test occursin("amenity", q.filters[1])
    @test occursin("hospital", q.filters[1])
end

@testset "build_query" begin
    q = OverpassQuery() |>
        within_bbox(45.0, -100.0, 47.0, -96.0) |>
        node_with_tag("amenity", "hospital") |>
        way_with_tag("healthcare", "*") |>
        recurse_down() |>
        output(:json)

    ql = build_query(q)
    @test occursin("[out:json]", ql)
    @test occursin("[timeout:", ql)
    @test occursin("amenity", ql)
    @test occursin("45.0", ql)
    @test occursin("out body", ql)
end

@testset "wildcard tag" begin
    q = OverpassQuery() |>
        within_bbox(45.0, -100.0, 47.0, -96.0) |>
        node_with_tag("healthcare")

    ql = build_query(q)
    @test occursin("[\"healthcare\"]", ql)
    @test !occursin("=\"*\"", ql)
end

# ── OsmData struct ────────────────────────────────────────────────────────────
@testset "OsmData construction" begin
    nodes = Dict{Int64, @NamedTuple{lat::Float64, lon::Float64, tags::Dict{String,String}}}(
        1 => (lat=46.0, lon=-97.0, tags=Dict("amenity"=>"hospital", "name"=>"Test Hospital")),
        2 => (lat=46.1, lon=-96.9, tags=Dict("amenity"=>"pharmacy")),
    )
    ways = Dict{Int64, @NamedTuple{nodes::Vector{Int64}, tags::Dict{String,String}}}()
    rels = Dict{Int64, @NamedTuple{members::Vector{Dict}, tags::Dict{String,String}}}()
    meta = (query_time="2026-01-01", api_version="0.6", note="test")
    data = OsmData(nodes, ways, rels, meta)

    @test length(data.nodes) == 2
    @test length(data.ways)  == 0
    @test data.nodes[1].lat  ≈ 46.0
    @test data.nodes[1].tags["amenity"] == "hospital"
end

# ── pois_to_df ────────────────────────────────────────────────────────────────
@testset "pois_to_df" begin
    nodes = Dict{Int64, @NamedTuple{lat::Float64, lon::Float64, tags::Dict{String,String}}}(
        101 => (lat=46.0, lon=-97.0, tags=Dict("amenity"=>"hospital", "name"=>"County Hospital",
                                                 "beds"=>"50", "emergency"=>"yes")),
        102 => (lat=46.2, lon=-97.1, tags=Dict("amenity"=>"pharmacy", "name"=>"Main St Pharmacy")),
        103 => (lat=46.3, lon=-97.2, tags=Dict("landuse"=>"residential")),  # non-healthcare
    )
    ways = Dict{Int64, @NamedTuple{nodes::Vector{Int64}, tags::Dict{String,String}}}()
    rels = Dict{Int64, @NamedTuple{members::Vector{Dict}, tags::Dict{String,String}}}()
    meta = (query_time="2026-01-01", api_version="0.6", note="")
    data = OsmData(nodes, ways, rels, meta)

    df = pois_to_df(data)
    @test nrow(df) == 2   # excludes non-healthcare node 103
    @test "name" ∈ names(df)
    @test "lat"  ∈ names(df)
    @test "lon"  ∈ names(df)
    hospital_row = filter(r -> !ismissing(r.name) && r.name == "County Hospital", df)
    @test nrow(hospital_row) == 1
end

# ── nodes_to_df ───────────────────────────────────────────────────────────────
@testset "nodes_to_df" begin
    nodes = Dict{Int64, @NamedTuple{lat::Float64, lon::Float64, tags::Dict{String,String}}}(
        1 => (lat=45.0, lon=-95.0, tags=Dict("name"=>"A")),
        2 => (lat=46.0, lon=-96.0, tags=Dict("name"=>"B")),
    )
    ways = Dict{Int64, @NamedTuple{nodes::Vector{Int64}, tags::Dict{String,String}}}()
    rels = Dict{Int64, @NamedTuple{members::Vector{Dict}, tags::Dict{String,String}}}()
    meta = (query_time="now", api_version="0.6", note="")
    data = OsmData(nodes, ways, rels, meta)

    df = nodes_to_df(data; tag_keys=["name"])
    @test nrow(df) == 2
    @test "id"   ∈ names(df)
    @test "lat"  ∈ names(df)
    @test "lon"  ∈ names(df)
    @test "name" ∈ names(df)
end

# ── Network query (skipped if no network) ────────────────────────────────────
@testset "run_query network (skipped if unavailable)" begin
    q = OverpassQuery() |>
        within_bbox(46.8, -100.8, 46.9, -100.7) |>
        node_with_tag("amenity", "hospital") |>
        output(:json)

    try
        data = run_query(q; use_cache=false)
        @test data isa OsmData
    catch e
        @warn "Overpass network test skipped: $e"
    end
end
