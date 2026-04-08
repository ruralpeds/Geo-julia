# csr_tests.jl — Complete Spatial Randomness tests

using Statistics
using Distributions

"""
    quadrat_test(pp; nx=5, ny=5) -> NamedTuple

Chi-squared quadrat test for Complete Spatial Randomness.
Divides the window into nx×ny quadrats and tests whether
observed counts follow a Poisson distribution.

Returns: (chi2, df, p_value, observed_counts, expected_count)
"""
function quadrat_test(pp::PointPattern{RectWindow};
                       nx::Int = 5, ny::Int = 5)

    w = pp.window
    xbreaks = range(w.xmin, w.xmax; length=nx+1)
    ybreaks = range(w.ymin, w.ymax; length=ny+1)

    observed = zeros(Int, nx, ny)
    for (x, y) in zip(pp.x, pp.y)
        i = min(searchsortedlast(xbreaks, x), nx)
        j = min(searchsortedlast(ybreaks, y), ny)
        i >= 1 && j >= 1 && (observed[i, j] += 1)
    end

    k = nx * ny
    expected = pp.n / k   # Poisson mean under CSR

    # Chi-squared test (combining cells with expected < 1)
    obs_vec = vec(observed)
    chi2 = sum((o - expected)^2 / expected for o in obs_vec)
    df   = k - 1
    p    = 1.0 - cdf(Chisq(df), chi2)

    (chi2=chi2, df=df, p_value=p,
     observed_counts=observed, expected_count=expected,
     n_quadrats=k, interpretation=(p < 0.05 ? "NOT CSR (clustered or regular)" : "Consistent with CSR"))
end

"""
    clarkevans_test(pp) -> NamedTuple

Clark-Evans nearest neighbour test for CSR.
Tests whether the mean nearest-neighbour distance differs from
the expected value under CSR: E[d] = 1 / (2√λ).

Returns: (R, z_score, p_value) where R < 1 = clustering, R > 1 = regularity.
"""
function clarkevans_test(pp::PointPattern)
    n = pp.n
    n < 2 && error("Need at least 2 points")

    # Observed mean nearest-neighbour distance
    pts  = Float64.(hcat(pp.x, pp.y)')
    tree = KDTree(pts)
    d_obs = Vector{Float64}(undef, n)
    for i in 1:n
        idxs, dists = knn(tree, pts[:,i], 2, true)  # k=2 to exclude self
        d_obs[i] = dists[2]  # nearest neighbour (not self)
    end
    d_mean = mean(d_obs)

    λ_hat = intensity(pp)
    d_exp = 1.0 / (2.0 * sqrt(λ_hat))
    σ_d   = sqrt((4 - π) / (4π * λ_hat * pp.n))

    R       = d_mean / d_exp
    z_score = (d_mean - d_exp) / σ_d
    p_value = 2.0 * (1.0 - _norm_cdf(abs(z_score)))

    (R=R, z_score=z_score, p_value=p_value,
     d_observed=d_mean, d_expected=d_exp,
     interpretation=(R < 1 ? "Clustered" : R > 1 ? "Regular" : "Random"))
end

# Normal CDF approximation
function _norm_cdf(z::Float64)::Float64
    t = 1.0 / (1.0 + 0.2316419 * abs(z))
    d = 0.3989423 * exp(-0.5 * z^2)
    p = 1.0 - d * t * @evalpoly(t, 1.330274429, -1.821255978, 1.781477937, -0.356563782, 0.319381530)
    z >= 0 ? p : 1.0 - p
end
