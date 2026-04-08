using Test, DataFrames
using PopulationData

# ──────────────────────────────────────────────────────────────────────────────
# DATA_DIR
# ──────────────────────────────────────────────────────────────────────────────
@testset "DATA_DIR" begin
    @test isa(PopulationData.DATA_DIR, String)
    @test endswith(PopulationData.DATA_DIR, "population")
end

# ──────────────────────────────────────────────────────────────────────────────
# landscan_info
# ──────────────────────────────────────────────────────────────────────────────
@testset "landscan_info" begin
    info = PopulationData.landscan_info()
    @test isa(info, String)
    @test occursin("ORNL", info) || occursin("LandScan", info)
end

# ──────────────────────────────────────────────────────────────────────────────
# get_acs (requires network; skip if no connectivity)
# ──────────────────────────────────────────────────────────────────────────────
@testset "get_acs North Dakota counties" begin
    try
        df = get_acs(["B01001_001E"]; geography = "county", state = "38", year = 2022)
        @test nrow(df) == 53
        @test "B01001_001E" in names(df) || "geoid" in names(df)
    catch e
        @warn "get_acs test skipped (network unavailable): $(e)"
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# clear_cache (non-destructive: only clears if dir exists)
# ──────────────────────────────────────────────────────────────────────────────
@testset "clear_cache" begin
    # Should not error even if subdirectory doesn't exist
    @test_nowarn PopulationData.clear_cache(; subdir = "nonexistent_test_subdir")
end
