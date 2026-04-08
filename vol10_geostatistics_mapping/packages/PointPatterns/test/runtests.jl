using Test, Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "src", "PointPatterns.jl"))
using .PointPatterns

function make_clustered(n=80; seed=1, n_clusters=4)
    rng     = MersenneTwister(seed)
    pts     = zeros(n, 2)
    centres = hcat(rand(rng, n_clusters) .* 8, rand(rng, n_clusters) .* 8)
    per_c   = n ÷ n_clusters
    for k in 1:n_clusters
        idx = (k-1)*per_c+1 : min(k*per_c, n)
        pts[idx,1] = centres[k,1] .+ 0.3*randn(rng, length(idx))
        pts[idx,2] = centres[k,2] .+ 0.3*randn(rng, length(idx))
    end
    pts
end

function make_csr(n=50; seed=2, width=10.0)
    rng = MersenneTwister(seed)
    hcat(rand(rng, n) .* width, rand(rng, n) .* width)
end

@testset "KDE — density integrates to ~1 over large grid" begin
    pts   = make_csr(60)
    area  = 10.0^2
    kr    = kde2d(pts; n_grid=25)
    # Each density value × cell area should sum to ~1
    bbox  = (kr.window[2]-kr.window[1]) * (kr.window[4]-kr.window[3])
    cell  = bbox / length(kr.density)
    total = sum(kr.density) * cell
    @test 0.5 <= total <= 2.0   # rough integration check
end

@testset "KDE — non-negative density" begin
    pts = make_clustered(60)
    kr  = kde2d(pts; bandwidth=1.0, kernel=:gaussian)
    @test all(kr.density .>= 0.0)
    @test kr.bandwidth == 1.0
end

@testset "KDE — Epanechnikov and quartic kernels" begin
    pts   = make_csr(40)
    kr_e  = kde2d(pts; bandwidth=2.0, kernel=:epanechnikov)
    kr_q  = kde2d(pts; bandwidth=2.0, kernel=:quartic)
    @test all(kr_e.density .>= 0.0)
    @test all(kr_q.density .>= 0.0)
end

@testset "Silverman bandwidth — positive" begin
    pts = make_csr(30)
    h   = silverman_bandwidth(pts)
    @test h > 0.0
    @test isfinite(h)
end

@testset "LCV bandwidth — in reasonable range" begin
    pts = make_csr(30)
    h_s = silverman_bandwidth(pts)
    h_l = lcv_bandwidth(pts; n_candidates=5)
    @test h_l > 0.0
    @test isfinite(h_l)
    @test h_l >= 0.01
end

@testset "Hotspot threshold" begin
    pts = make_clustered(60)
    kr  = kde2d(pts; bandwidth=0.8)
    thr = hotspot_threshold(kr; quantile_level=0.9)
    @test thr >= 0.0
    @test sum(kr.density .>= thr) ≈ length(kr.density) * 0.1 atol=5
end

@testset "Ripley K — CSR pattern" begin
    rng = MersenneTwister(3)
    pts = make_csr(50; seed=3)
    kr  = ripley_k(pts, 100.0; n_r=10, n_sim=49, rng=rng)
    @test length(kr.K)   == 10
    @test all(kr.K .>= 0.0)
    @test all(kr.K_csr .>= 0.0)
    @test length(kr.K_lo) == 10
    @test all(kr.K_lo .<= kr.K_hi)
    @test 0.0 <= kr.p_value <= 1.0
end

@testset "Ripley K — L function" begin
    rng = MersenneTwister(4)
    pts = make_csr(40; seed=4)
    kr  = ripley_k(pts, 100.0; n_r=8, n_sim=29, rng=rng)
    # L(r) = sqrt(K(r)/π) - r; should be ≈ 0 for CSR
    @test all(isfinite.(kr.L))
end

@testset "Ripley K — clustered > CSR at small r" begin
    rng = MersenneTwister(5)
    pts = make_clustered(60; seed=5)
    kr  = ripley_k(pts, 100.0; n_r=10, n_sim=49, rng=rng)
    # For clustered pattern, K should exceed πr² at small r
    k_ratio = kr.K ./ max.(kr.K_csr, 1e-10)
    @test mean(k_ratio[1:5]) > 1.0
end

@testset "G function — NND distribution" begin
    rng = MersenneTwister(6)
    pts = make_csr(50; seed=6)
    gf  = nnd_distribution(pts, 100.0; n_r=10, n_sim=49, rng=rng)
    @test all(0.0 .<= gf.G .<= 1.0)
    @test issorted(gf.G)   # ECDF is non-decreasing
    @test 0.0 <= gf.p_value <= 1.0
    @test gf.λ ≈ 50/100.0 atol=1e-10
end

@testset "Pair correlation function" begin
    pts = make_csr(40)
    pc  = pair_correlation(pts, 100.0; n_r=10)
    @test length(pc.r) == 10
    @test all(isfinite.(pc.g))
end

@testset "DBSCAN — recovers clusters" begin
    pts = make_clustered(40; seed=7, n_clusters=3)
    db  = dbscan(pts; ε=0.8, min_pts=3)
    @test db.n_clusters >= 2   # should find at least 2 of the 3 clusters
    @test length(db.labels) == 40
    @test all(db.labels .>= 0)
end

@testset "DBSCAN — pure noise" begin
    rng = MersenneTwister(8)
    pts = hcat(rand(rng,20)*100, rand(rng,20)*100)  # very spread out
    db  = dbscan(pts; ε=0.5, min_pts=3)
    @test db.n_clusters == 0 || db.n_noise >= 10
end

@testset "Knox test — space-time clustering" begin
    rng    = MersenneTwister(9)
    n      = 30
    coords = hcat(rand(rng, n)*10, rand(rng, n)*10)
    times  = rand(rng, n) * 100.0
    kr     = knox_test(coords, times; d_thresh=2.0, t_thresh=10.0, n_perm=99, rng=rng)
    @test kr.observed >= 0
    @test 0.0 <= kr.p_value <= 1.0
    @test isfinite(kr.ratio)
end

@testset "Knox test — injected space-time cluster" begin
    rng  = MersenneTwister(10)
    n    = 40
    # Create clustered cases near (5,5) at time ~50
    x    = vcat(randn(rng, 10)*0.3 .+ 5, rand(rng, 30)*10)
    y    = vcat(randn(rng, 10)*0.3 .+ 5, rand(rng, 30)*10)
    t    = vcat(randn(rng, 10)*1.0 .+ 50, rand(rng, 30)*100)
    c    = hcat(x, y)
    kr   = knox_test(c, t; d_thresh=1.0, t_thresh=5.0, n_perm=99, rng=rng)
    @test kr.observed > 0
    @test kr.ratio > 1.0  # more space-time pairs than expected
end

@testset "Spatial scan points" begin
    rng      = MersenneTwister(11)
    n_cases  = 25; n_ctrl = 75
    # Cases clustered in corner
    cases    = hcat(rand(rng, n_cases)*2, rand(rng, n_cases)*2)
    controls = hcat(rand(rng, n_ctrl)*10, rand(rng, n_ctrl)*10)
    sr       = spatial_scan_points(cases, controls; n_sim=49, rng=rng)
    @test isa(sr, ScanPointResult)
    @test sr.llr >= 0.0
    @test 0.0 <= sr.p_value <= 1.0
    @test sr.n_cases + sr.n_controls <= n_cases + n_ctrl
end

@testset "PointPatternReport" begin
    rng = MersenneTwister(12)
    pts = make_csr(40; seed=12)
    rpt = point_pattern_report(pts, 100.0; n_sim=49, rng=rng)
    @test isa(rpt, PointPatternReport)
    @test rpt.n_points == 40
    @test isfinite(rpt.intensity)
    @test 0.0 <= rpt.k_p_value <= 1.0
end
