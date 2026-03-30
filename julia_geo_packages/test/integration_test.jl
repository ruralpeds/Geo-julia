#!/usr/bin/env julia
# julia_geo_packages/test/integration_test.jl
#
# Full cross-package integration test for Vol 3 packages.
# Tests the complete pipeline: spatial weights → autocorrelation →
# classification → geocoding validation → Overpass query building
#
# Run: julia --project=. test/integration_test.jl
#
# Vol 3 — Julia Package Engineering, Chapter 25.2

using Test
using Random
using SparseArrays
using DataFrames

# ── Activate the workspace and load packages ──────────────────────────────────
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using SpatialStats
using MapClassify
using Geocode
using Overpass

Random.seed!(2026)

# ── Shared test data ──────────────────────────────────────────────────────────

const N = 53  # North Dakota counties (canonical test size)

# Build a synthetic ring/chain weight matrix (n observations, n-1 neighbours on each side)
function make_test_weights(n::Int)
    Is = Int[]; Js = Int[]; Vs = Float64[]
    for i in 1:n-1
        push!(Is, i, i+1); push!(Js, i+1, i); push!(Vs, 1.0, 1.0)
    end
    W = sparse(Is, Js, Vs, n, n)
    # Row-standardise
    row_sums = vec(sum(W; dims=2))
    rows, cols, vals = findnz(W)
    for k in eachindex(rows)
        vals[k] /= row_sums[rows[k]]
    end
    W = sparse(rows, cols, vals, n, n)
    SpatialStats.SpatialWeights(W, n,
        SpatialStats.RowStandardizedStyle(),
        SpatialStats.DistanceTransform(), 0, 1.8, 1, 2)
end

const W_TEST = make_test_weights(N)

# ── Integration test 1: SpatialStats pipeline ────────────────────────────────
@testset "Integration: SpatialStats" begin

    @testset "spatial weights structure" begin
        @test W_TEST.n == N
        @test W_TEST.island_count == 0
        @test W_TEST.style isa SpatialStats.RowStandardizedStyle

        # Row sums should all be 1.0
        row_sums = vec(sum(W_TEST.W; dims=2))
        @test all(abs.(row_sums .- 1.0) .< 1e-9)
    end

    @testset "lag_spatial" begin
        y = Float64.(1:N)
        lag = lag_spatial(W_TEST, y)
        @test length(lag) == N
        @test eltype(lag) == Float64
        # Node 1 has only node 2 as neighbour
        @test lag[1] ≈ 2.0
        # Middle node i has neighbours i-1 and i+1, each with weight 0.5
        mid = 27
        @test lag[mid] ≈ (mid - 1 + mid + 1) * 0.5
    end

    @testset "moran clustered → positive I" begin
        y_clust = vcat(fill(10.0, div(N,2)), fill(1.0, N - div(N,2)))
        r = moran(y_clust, W_TEST; permutations=499)
        @test r.I > 0.3
        @test r.p_value < 0.05
        @test r.method == :permutation
    end

    @testset "moran random → near-zero I" begin
        y_rand = randn(N)
        r = moran(y_rand, W_TEST; permutations=199)
        @test -1.0 <= r.I <= 1.0
        @test 0.0 <= r.p_value <= 1.0
    end

    @testset "moran analytical" begin
        y = randn(N)
        r = moran(y, W_TEST; method=:analytical)
        @test r.method == :analytical
        @test -1.0 <= r.I <= 1.0
    end

    @testset "geary C" begin
        y_clust = vcat(fill(10.0, div(N,2)), fill(1.0, N - div(N,2)))
        r = geary(y_clust, W_TEST; permutations=199)
        @test r.I < 1.0  # positive autocorrelation → C < 1
        @test 0.0 <= r.p_value <= 1.0
    end

    @testset "LISA clusters" begin
        y = vcat(fill(10.0, div(N,2)), fill(1.0, N - div(N,2)))
        r = lisa(y, W_TEST; permutations=199, alpha=0.05)
        @test length(r.cluster_type) == N
        @test all(t ∈ (:HH, :LL, :HL, :LH, :NS) for t in r.cluster_type)
        @test r.n == N
        @test r.significance == 0.05
        # Strong spatial pattern: should have HH and LL clusters
        @test count(==(:HH), r.cluster_type) > 0
        @test count(==(:LL), r.cluster_type) > 0
    end

    @testset "moran_local is alias for lisa" begin
        y = randn(N)
        r1 = lisa(y, W_TEST; permutations=99)
        r2 = moran_local(y, W_TEST; permutations=99)
        @test r1.n == r2.n
    end

    @testset "Getis-Ord G*" begin
        y = abs.(randn(N)) .+ 1.0
        r = getis_ord(y, W_TEST; star=true, permutations=99)
        @test length(r.z_scores)  == N
        @test all(0.0 .<= r.p_values .<= 1.0)
        @test r.star == true
    end

    @testset "OLS + LM tests" begin
        X = hcat(ones(N), randn(N))
        y = X * [2.0, 3.0] + 0.5 * randn(N)
        r = lm_spatial(y, X, W_TEST; coef_names=["intercept","x1"])
        @test r.model_type == :OLS
        @test r.r_squared > 0.5
        @test 0.0 <= r.lm_lag_p  <= 1.0
        @test 0.0 <= r.lm_error_p <= 1.0
    end

    @testset "Spatial Lag Model" begin
        X = hcat(ones(N), randn(N))
        y = X * [1.0, 2.0] + 0.3 * randn(N)
        r = slm(y, X, W_TEST)
        @test r.model_type == :SLM
        @test -1.0 <= r.rho_or_lambda <= 1.0
        @test r.AIC < Inf
        @test length(r.residuals) == N
    end

    @testset "Spatial Error Model" begin
        X = hcat(ones(N), randn(N))
        y = X * [1.0, 2.0] + 0.3 * randn(N)
        r = sem(y, X, W_TEST)
        @test r.model_type == :SEM
        @test r.AIC < Inf
    end

    @testset "Spatial Durbin Model" begin
        X = hcat(ones(N), randn(N), randn(N))
        y = X * [1.0, 2.0, -1.0] + 0.3 * randn(N)
        r = sdm(y, X, W_TEST)
        @test r.model_type == :SDM
        @test length(r.coefficients) > 3  # original + lagged predictors
    end
end

# ── Integration test 2: MapClassify pipeline ─────────────────────────────────
@testset "Integration: MapClassify" begin

    # Simulate county-level provider density (skewed)
    provider_density = abs.(randn(N)) .* 5.0 .+ 1.0
    sort!(provider_density; rev=true)
    # Add heavy tail
    provider_density[1:3] .= [50.0, 35.0, 25.0]

    @testset "NaturalBreaks (Fisher-Jenks)" begin
        r = classify(provider_density, NaturalBreaks(5))
        @test r.k == 5
        @test all(1 .<= r.assignments .<= 5)
        @test r.gvf > 0.7  # should fit well
        @test sum(r.counts) == N
    end

    @testset "Quantiles" begin
        r = classify(provider_density, Quantiles(5))
        @test r.k == 5
        # Each class should have ≈ N/5 = ~10-11 observations
        @test all(abs(c - N÷5) <= 3 for c in r.counts)
    end

    @testset "NaturalBreaks GVF > EqualInterval GVF" begin
        r_nb = classify(provider_density, NaturalBreaks(5))
        r_ei = classify(provider_density, EqualInterval(5))
        @test r_nb.gvf >= r_ei.gvf - 1e-9
    end

    @testset "HeadTailBreaks on skewed data" begin
        r = classify(provider_density, HeadTailBreaks())
        @test r.k >= 2  # should create multiple classes on skewed data
        @test all(1 .<= r.assignments .<= r.k)
    end

    @testset "compare_classifiers" begin
        df = compare_classifiers(provider_density, 5)
        @test "scheme" ∈ names(df)
        @test "gvf"    ∈ names(df)
        @test nrow(df) >= 5
    end

    @testset "choropleth_classify symbols" begin
        for sym in [:NaturalBreaks, :Quantiles, :EqualInterval, :JenksCaspall]
            r = choropleth_classify(provider_density, 5; scheme=sym)
            @test r.k == 5
            @test all(1 .<= r.assignments .<= 5)
        end
    end

    @testset "UserDefined breaks" begin
        breaks = [5.0, 15.0, 30.0, maximum(provider_density)]
        r = classify(provider_density, UserDefined(breaks))
        @test r.k == 4
        @test sum(r.counts) == N
    end
end

# ── Integration test 3: Geocode validation ────────────────────────────────────
@testset "Integration: Geocode" begin

    @testset "address normalisation" begin
        @test normalize_address("123 Main St.")        == "123 Main Street"
        @test normalize_address("456 Oak Ave")         == "456 Oak Avenue"
        @test normalize_address("789 Pine Blvd.")      == "789 Pine Boulevard"
        @test normalize_address("100 N. Main Rd")      == "100 North Main Road"
        @test normalize_address("Apt. 2B, 5 Elm Dr.")  == "Apt 2B, 5 Elm Drive"
    end

    @testset "P.O. Box detection" begin
        @test is_po_box("P.O. Box 123")
        @test is_po_box("PO Box 456")
        @test is_po_box("Post Office Box 100")
        @test !is_po_box("123 Main Street")
    end

    @testset "rural route detection" begin
        @test is_rural_route("RR 1")
        @test is_rural_route("HC 61 Box 10")
        @test is_rural_route("General Delivery")
        @test !is_rural_route("500 University Ave")
    end

    @testset "state standardisation" begin
        @test standardize_state("ND")           == "ND"
        @test standardize_state("North Dakota")  == "ND"
        @test standardize_state("north dakota")  == "ND"
        @test standardize_state("Montana")       == "MT"
        @test standardize_state("south dakota")  == "SD"
        @test standardize_state("Wyoming")       == "WY"
    end

    @testset "GeocodedAddress type" begin
        ga = GeocodedAddress("1", "600 E Boulevard Dr, Bismarck, ND",
                              "600 East Boulevard Drive, Bismarck, ND 58505",
                              46.8083, -100.7837, "Match", "38015000100", 95.0, :census)
        @test ga.lat ≈ 46.8083
        @test ga.lon ≈ -100.7837
        @test ga.match_type == "Match"
        @test ga.backend == :census
        @test length(ga.tract_fips) == 11
    end

    @testset "NominatimGeocoder validation" begin
        @test_throws ErrorException NominatimGeocoder(; user_agent="")
        g = NominatimGeocoder(; user_agent="IntegrationTest/1.0")
        @test g.sleep_sec >= 1.0
    end

    @testset "Census geocode (network; skip if unavailable)" begin
        addrs = DataFrame(
            id     = ["1"],
            street = ["600 E Boulevard Dr"],
            city   = ["Bismarck"],
            state  = ["ND"],
            zip    = ["58505"],
        )
        try
            results = geocode_all(addrs; backend=CensusGeocoder(), batch_size=500)
            @test nrow(results) == 1
            @test "lat" ∈ names(results)
        catch e
            @warn "Census geocode network test skipped: $e"
        end
    end
end

# ── Integration test 4: Overpass query builder ───────────────────────────────
@testset "Integration: Overpass" begin

    @testset "fluent builder" begin
        q = OverpassQuery() |>
            within_bbox(45.0, -100.0, 47.0, -96.0) |>
            node_with_tag("amenity", "hospital") |>
            way_with_tag("healthcare", "*") |>
            recurse_down() |>
            output(:json)

        @test q.bbox == (45.0, -100.0, 47.0, -96.0)
        @test q.recurse == true
        @test q.out_mode == :json
        @test length(q.filters) == 2
    end

    @testset "build_query QL syntax" begin
        q = OverpassQuery() |>
            within_bbox(46.0, -98.0, 47.0, -97.0) |>
            node_with_tag("amenity", "hospital") |>
            output(:json)

        ql = build_query(q)
        @test occursin("[out:json]", ql)
        @test occursin("[timeout:", ql)
        @test occursin("amenity", ql)
        @test occursin("hospital", ql)
        @test occursin("46.0", ql)
        @test occursin("out body", ql)
    end

    @testset "wildcard tag syntax" begin
        q = OverpassQuery() |>
            within_bbox(45.0, -100.0, 47.0, -96.0) |>
            node_with_tag("healthcare")

        ql = build_query(q)
        @test occursin("[\"healthcare\"]", ql)
        @test !occursin("=\"*\"", ql)
    end

    @testset "OsmData construction and conversion" begin
        nodes = Dict{Int64, @NamedTuple{lat::Float64, lon::Float64, tags::Dict{String,String}}}(
            1001 => (lat=46.5, lon=-97.2, tags=Dict("amenity"=>"hospital",
                                                      "name"=>"Cass County Medical",
                                                      "beds"=>"120")),
            1002 => (lat=46.6, lon=-97.3, tags=Dict("amenity"=>"pharmacy",
                                                      "name"=>"Main Street Pharmacy")),
            1003 => (lat=46.7, lon=-97.4, tags=Dict("landuse"=>"residential")),
        )
        ways = Dict{Int64, @NamedTuple{nodes::Vector{Int64}, tags::Dict{String,String}}}()
        rels = Dict{Int64, @NamedTuple{members::Vector{Dict}, tags::Dict{String,String}}}()
        meta = (query_time="2026-03-30", api_version="0.6", note="integration test")
        data = OsmData(nodes, ways, rels, meta)

        @test length(data.nodes) == 3
        @test data.nodes[1001].lat ≈ 46.5
        @test data.nodes[1001].tags["amenity"] == "hospital"

        # pois_to_df filters to healthcare nodes only
        df = pois_to_df(data)
        @test nrow(df) == 2  # excludes node 1003 (landuse=residential)
        @test "name" ∈ names(df)
        hospital = filter(r -> !ismissing(r.name) && r.name == "Cass County Medical", df)
        @test nrow(hospital) == 1
    end

    @testset "nodes_to_df" begin
        nodes = Dict{Int64, @NamedTuple{lat::Float64, lon::Float64, tags::Dict{String,String}}}(
            i => (lat=46.0+i*0.1, lon=-97.0-i*0.1, tags=Dict("name"=>"Node $i"))
            for i in 1:5
        )
        ways = Dict{Int64, @NamedTuple{nodes::Vector{Int64}, tags::Dict{String,String}}}()
        rels = Dict{Int64, @NamedTuple{members::Vector{Dict}, tags::Dict{String,String}}}()
        meta = (query_time="now", api_version="0.6", note="")
        data = OsmData(nodes, ways, rels, meta)

        df = nodes_to_df(data; tag_keys=["name"])
        @test nrow(df) == 5
        @test "name" ∈ names(df)
        @test all(!ismissing(n) for n in df.name)
    end

    @testset "Overpass network (skip if unavailable)" begin
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
end

println("\n=== Vol 3 Integration Tests Complete ===")
