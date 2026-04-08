#!/usr/bin/env julia
# scripts/point_patterns.jl
# Spatial point pattern analysis of ND incident case locations

using Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "packages", "PointPatterns", "src", "PointPatterns.jl"))
using .PointPatterns

println("=" ^ 65)
println("  Vol 10 — Point Pattern Analysis: ND Incident Cases")
println("  KDE · Ripley K/L/G · DBSCAN · Knox Test · Scan")
println("=" ^ 65)

# ── Simulated ND incident case data ──────────────────────────────────────────

function make_nd_cases(n=120; seed=7)
    rng = MersenneTwister(seed)
    # ND bounding box (degrees): lon ∈ [-104.1,-96.5], lat ∈ [45.9,49.0]
    # Rescale to unit box [0,10]² for pattern analysis
    x_scale = 7.6; y_scale = 3.1

    pts = zeros(n, 2)
    # 60% background CSR
    n_bg = round(Int, 0.6n)
    pts[1:n_bg, 1] = rand(rng, n_bg) .* x_scale
    pts[1:n_bg, 2] = rand(rng, n_bg) .* y_scale

    # Cluster 1: northwest (rural healthcare desert)
    n_c1 = round(Int, 0.25n)
    pts[n_bg+1:n_bg+n_c1, 1] = 0.5 .+ 0.4 .* randn(rng, n_c1)
    pts[n_bg+1:n_bg+n_c1, 2] = 2.5 .+ 0.4 .* randn(rng, n_c1)

    # Cluster 2: southeast (Fargo metro)
    n_c2 = n - n_bg - n_c1
    pts[n_bg+n_c1+1:end, 1] = 7.0 .+ 0.5 .* randn(rng, n_c2)
    pts[n_bg+n_c1+1:end, 2] = 0.5 .+ 0.5 .* randn(rng, n_c2)

    pts = clamp.(pts, 0.01, [x_scale-0.01 y_scale-0.01][ones(Int,n),:])
    pts
end

function make_nd_controls(n=300; seed=11)
    rng = MersenneTwister(seed)
    hcat(rand(rng, n) .* 7.6, rand(rng, n) .* 3.1)
end

function make_nd_spacetime(n=80; seed=17)
    rng    = MersenneTwister(seed)
    coords = make_nd_cases(n; seed=seed)
    # Cases arrive in two temporal waves ~week 10 and ~week 30
    labels = rand(rng, n) .< 0.5
    times  = ifelse.(labels,
                     8.0  .+ 4.0 .* randn(rng, n),
                     28.0 .+ 4.0 .* randn(rng, n))
    times  = clamp.(times, 0.0, 52.0)
    (coords=coords, times=times)
end

pts      = make_nd_cases()
controls = make_nd_controls()
st       = make_nd_spacetime()
area     = 7.6 * 3.1   # bounding box area (degree²)

println("\n► $(size(pts,1)) incident cases  |  $(size(controls,1)) controls")
println("  Study area: $(round(area, digits=2)) deg²")

# ── Section 1: Kernel Density Estimation ─────────────────────────────────────

println("\n[1] Kernel Density Estimation")
h_silver = silverman_bandwidth(pts)
println("  Silverman bandwidth: $(round(h_silver, digits=4))")

rng_lcv = MersenneTwister(1)
h_lcv   = lcv_bandwidth(pts; n_candidates=6)
println("  LCV bandwidth:       $(round(h_lcv, digits=4))")

# Gaussian KDE
kr_gauss = kde2d(pts; bandwidth=h_silver, kernel=:gaussian)
println("  Gaussian KDE: $(length(kr_gauss.density)) grid cells  " *
        "max density=$(round(maximum(kr_gauss.density), digits=4))")

# Epanechnikov and quartic
kr_ep   = kde2d(pts; bandwidth=h_silver, kernel=:epanechnikov)
kr_quar = kde2d(pts; bandwidth=h_silver, kernel=:quartic)
println("  Epanechnikov KDE max: $(round(maximum(kr_ep.density), digits=4))")
println("  Quartic KDE max:      $(round(maximum(kr_quar.density), digits=4))")

# Hotspot threshold
thr_95 = hotspot_threshold(kr_gauss; quantile_level=0.95)
n_hot  = sum(kr_gauss.density .>= thr_95)
println("  95th-pctile hotspot threshold: $(round(thr_95, digits=4))")
println("  Hotspot cells (top 5%): $n_hot / $(length(kr_gauss.density))")

λ̂ = kde_intensity(kr_gauss)
println("  Estimated intensity: $(round(λ̂, digits=3)) events/unit area")

# ── Section 2: Ripley's K / L function ───────────────────────────────────────

println("\n[2] Ripley's K and L Functions")
rng_k = MersenneTwister(3)
kr    = ripley_k(pts, area; n_r=12, n_sim=99, rng=rng_k)
println("  r values: $(round.(kr.r[1:3], digits=3))...")
println("  K(r) at r[3]: $(round(kr.K[3],digits=4))  CSR: $(round(kr.K_csr[3],digits=4))")
println("  L(r) at r[3]: $(round(kr.L[3],digits=4))")
println("  K p-value (CSR test): $(round(kr.p_value, digits=3))")

# Check for clustering: K > K_csr at small scales
n_exceed = sum(kr.K .> kr.K_csr)
println("  K > K_csr at $(n_exceed)/$(length(kr.r)) distance bands → $(n_exceed > length(kr.r)/2 ? "clustering" : "regularity/CSR")")

# ── Section 3: G function (NND distribution) ─────────────────────────────────

println("\n[3] G Function (Nearest-Neighbour Distance Distribution)")
rng_g = MersenneTwister(4)
gf    = nnd_distribution(pts, area; n_r=12, n_sim=99, rng=rng_g)
println("  λ̂ = $(round(gf.λ, digits=4))")
println("  G(r) range: [$(round(minimum(gf.G),digits=3)), $(round(maximum(gf.G),digits=3))]")
println("  G p-value (CSR test): $(round(gf.p_value, digits=3))")
println("  G(r) > G_CSR(r) at median r: $(gf.G[6] > gf.G_csr[6] ? "yes (clustering)" : "no")")

# ── Section 4: Pair Correlation Function ─────────────────────────────────────

println("\n[4] Pair Correlation Function g(r)")
pc = pair_correlation(pts, area; n_r=12)
println("  r[1]=$(round(pc.r[1],digits=3))  g[1]=$(round(pc.g[1],digits=3))  (>1 = clustering)")
println("  r[6]=$(round(pc.r[6],digits=3))  g[6]=$(round(pc.g[6],digits=3))")
println("  r > 1 at $(sum(pc.g .> 1.0))/$(length(pc.g)) scales")

# ── Section 5: DBSCAN Clustering ─────────────────────────────────────────────

println("\n[5] DBSCAN Spatial Clustering")
h_use = h_silver
db1   = dbscan(pts; ε=h_use,       min_pts=4)
db2   = dbscan(pts; ε=h_use*1.5,   min_pts=4)
db3   = dbscan(pts; ε=h_use*2.0,   min_pts=4)
println("  ε=$(round(h_use,digits=3)):     $(db1.n_clusters) clusters  noise=$(db1.n_noise)")
println("  ε=$(round(h_use*1.5,digits=3)): $(db2.n_clusters) clusters  noise=$(db2.n_noise)")
println("  ε=$(round(h_use*2.0,digits=3)): $(db3.n_clusters) clusters  noise=$(db3.n_noise)")
if db2.n_clusters > 0
    println("  Cluster sizes (ε=$(round(h_use*1.5,digits=3))): $(sort(db2.cluster_sizes, rev=true))")
end

# ── Section 6: Knox Space-Time Test ──────────────────────────────────────────

println("\n[6] Knox Space-Time Clustering Test")
rng_kn = MersenneTwister(5)
kt     = knox_test(st.coords, st.times;
                   d_thresh=1.0, t_thresh=8.0, n_perm=199, rng=rng_kn)
println("  d_thresh=1.0  t_thresh=8.0 weeks")
println("  Observed close pairs: $(kt.observed)")
println("  Expected (H₀):        $(round(kt.expected, digits=2))")
println("  Ratio obs/exp:        $(round(kt.ratio, digits=3))")
println("  Monte Carlo p-value:  $(round(kt.p_value, digits=4))")
println("  Space-time clustering: $(kt.ratio > 1.2 && kt.p_value < 0.05 ? "DETECTED" : "not significant")")

# ── Section 7: Bernoulli Spatial Scan ────────────────────────────────────────

println("\n[7] Bernoulli Spatial Scan Statistic (case-control)")
rng_sc = MersenneTwister(6)
sr     = spatial_scan_points(pts, controls; n_sim=99, rng=rng_sc)
println("  Most likely cluster:")
println("    Centre: point $(sr.centre_idx)  Radius: $(round(sr.radius, digits=3))")
println("    Cases in: $(sr.n_cases)  Controls in: $(sr.n_controls)")
println("    LLR: $(round(sr.llr, digits=4))   p-value: $(round(sr.p_value, digits=4))")
println("    Significant: $(sr.significant ? "YES" : "no")")

# ── Section 8: Full report ────────────────────────────────────────────────────

println("\n[8] Point Pattern Report")
rng_rpt = MersenneTwister(77)
rpt     = point_pattern_report(pts, area;
                                pattern_name="ND-Incident-Cases",
                                n_sim=99, rng=rng_rpt)
print_point_pattern_report(rpt)

println("\n✓ Point pattern analysis complete.")
