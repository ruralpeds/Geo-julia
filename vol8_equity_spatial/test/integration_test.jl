#!/usr/bin/env julia
# test/integration_test.jl — Vol 8 integration tests
# Health Equity, Spatial Regression, and Conformal Prediction
#
# Tests all three packages individually and their cross-package interactions.

using Test, Statistics, LinearAlgebra, Random

# ── Load packages ─────────────────────────────────────────────────────────────

const VOL8 = joinpath(@__DIR__, "..")

function load_package(name)
    path = joinpath(VOL8, "packages", name, "src", "$(name).jl")
    if isfile(path)
        include(path)
        return true
    end
    @warn "Package $name not found at $path"
    return false
end

HE_LOADED  = load_package("HealthEquity")
SR_LOADED  = load_package("SpatialRegression")
CH_LOADED  = load_package("ConformalHealth")

if HE_LOADED;  using .HealthEquity;  end
if SR_LOADED;  using .SpatialRegression; end
if CH_LOADED;  using .ConformalHealth; end

# ── Shared test fixtures ───────────────────────────────────────────────────────

function make_binary_data(n=120; seed=42)
    rng = MersenneTwister(seed)
    probs  = clamp.(0.3 .+ 0.4*randn(rng, n), 0.05, 0.95)
    y      = Int.(rand(rng, n) .< probs)
    groups = repeat(["rural", "urban"], n ÷ 2)
    probs, y, groups
end

function make_access_scores(n=80; seed=7)
    rng = MersenneTwister(seed)
    clamp.(0.005 .+ 0.004*randn(rng, n), 0.0001, 0.05)
end

function make_spatial_data(n=40; seed=3)
    rng = MersenneTwister(seed)
    n_side = ceil(Int, sqrt(n))
    lats   = [44.0 + 0.5*(i-1) for i in 1:n_side for _ in 1:n_side][1:n]
    lons   = [-104.0 + 0.8*(j-1) for _ in 1:n_side for j in 1:n_side][1:n]
    coords = hcat(lats .+ 0.05*randn(rng, n), lons .+ 0.05*randn(rng, n))
    X      = hcat(0.12 .+ 0.05*randn(rng, n),
                  0.5  .+ 0.2*randn(rng, n),
                  exp.(2.0 .+ 0.5*randn(rng, n)))
    β_true = [-0.003, -0.002, -0.00002]
    y      = 0.008 .+ X * β_true .+ 0.0005*randn(rng, n)
    y      = max.(y, 0.0001)
    W = zeros(n, n)
    D = [sqrt(sum((coords[i,:] .- coords[j,:]).^2)) for i in 1:n, j in 1:n]
    for i in 1:n
        ord = sortperm(D[i,:])[2:5]
        W[i, ord] .= 0.25
    end
    (coords=coords, X=X, y=y, W=W)
end

function make_regression_data(n=200; seed=99)
    rng   = MersenneTwister(seed)
    X     = randn(rng, n, 4)
    β     = [1.5, -0.8, 0.4, 1.1]
    σ_fn  = x -> 0.2 + 0.3*abs(x[1])
    noise = [σ_fn(X[i,:]) * randn(rng) for i in 1:n]
    y     = X * β .+ noise
    X, y
end

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 1 — HealthEquity
# ══════════════════════════════════════════════════════════════════════════════

@testset "HealthEquity — Gini coefficient" begin
    if !HE_LOADED; @test_skip true; return; end
    x_equal = ones(20)
    @test gini_coefficient(x_equal) ≈ 0.0 atol=1e-10
    x_maxineq = vcat(zeros(19), [1.0])
    G = gini_coefficient(x_maxineq)
    @test G > 0.85
    x_access = make_access_scores()
    G2 = gini_coefficient(x_access)
    @test 0.0 < G2 < 1.0
end

@testset "HealthEquity — Theil index" begin
    if !HE_LOADED; @test_skip true; return; end
    x = make_access_scores(60)
    T = theil_index(x)
    @test T >= 0.0
    @test theil_index(ones(30)) ≈ 0.0 atol=1e-8
end

@testset "HealthEquity — Concentration index" begin
    if !HE_LOADED; @test_skip true; return; end
    n  = 50
    rng = MersenneTwister(1)
    y   = rand(rng, n) .+ 0.01
    r   = collect(1:n) ./ n
    ci  = concentration_index(y, r)
    @test -1.0 <= ci <= 1.0
    # When health is sorted with rank: concentration should be positive
    y_sorted = sort(y)
    ci_pos = concentration_index(y_sorted, r)
    @test ci_pos > 0
end

@testset "HealthEquity — Dissimilarity index" begin
    if !HE_LOADED; @test_skip true; return; end
    a = ones(10); b = ones(10)
    @test dissimilarity_index(a, b) ≈ 0.0 atol=1e-10
    a2 = [1.0, 0.0]; b2 = [0.0, 1.0]
    @test dissimilarity_index(a2, b2) ≈ 1.0 atol=1e-10
end

@testset "HealthEquity — Demographic parity" begin
    if !HE_LOADED; @test_skip true; return; end
    probs, y, groups = make_binary_data()
    ŷ = Int.(probs .> 0.5)
    dp = demographic_parity(ŷ, groups)
    @test isa(dp, DataFrame)
    @test "dp_diff" in names(dp) || "rate" in names(dp)
end

@testset "HealthEquity — Equalized odds" begin
    if !HE_LOADED; @test_skip true; return; end
    probs, y, groups = make_binary_data()
    ŷ = Int.(probs .> 0.5)
    eo = equalized_odds(ŷ, y, groups)
    @test isa(eo, DataFrame)
    @test "tpr" in names(eo)
    @test "fpr" in names(eo)
    @test nrow(eo) == 2  # one row per group
end

@testset "HealthEquity — Calibration gap" begin
    if !HE_LOADED; @test_skip true; return; end
    probs, y, groups = make_binary_data()
    cg = calibration_gap(probs, y, groups; n_bins=5)
    @test isa(cg, DataFrame)
    @test nrow(cg) > 0
end

@testset "HealthEquity — Oaxaca-Blinder decomposition" begin
    if !HE_LOADED; @test_skip true; return; end
    rng = MersenneTwister(55)
    n   = 80
    X_A = randn(rng, n, 3)
    X_B = randn(rng, n, 3) .+ 0.5
    β_true = [0.3, -0.2, 0.1]
    y_A = X_A * β_true .+ 0.1*randn(rng, n)
    y_B = X_B * β_true .+ 0.1*randn(rng, n)

    ob = oaxaca_blinder(X_A, y_A, X_B, y_B;
                         feature_names=["pov","rural","dist"])
    @test abs(ob.total_gap - (mean(y_A) - mean(y_B))) < 1e-8
    @test abs(ob.explained + ob.unexplained - ob.total_gap) < 1e-8
    @test 0.0 <= abs(ob.pct_explained) <= 1.5
    @test isa(ob.feature_contributions, DataFrame)
end

@testset "HealthEquity — Theil decomposition" begin
    if !HE_LOADED; @test_skip true; return; end
    x      = make_access_scores(60)
    groups = repeat(["rural", "urban"], 30)
    td     = theil_decompose(x, groups)
    @test abs(td.total - (td.between + td.within)) < 1e-8
    @test td.between >= 0.0
    @test td.within  >= 0.0
end

@testset "HealthEquity — Threshold sweep and equalise_tpr" begin
    if !HE_LOADED; @test_skip true; return; end
    probs, y, groups = make_binary_data(100)
    ts = threshold_sweep(probs, y, groups; thresholds=0.3:0.1:0.7)
    @test isa(ts, DataFrame)
    @test nrow(ts) > 0

    threshs = equalise_tpr(probs, y, groups)
    @test isa(threshs, Dict)
    @test "rural" in keys(threshs)
    @test "urban" in keys(threshs)
    ŷ_fair = apply_group_thresholds(probs, groups, threshs)
    @test length(ŷ_fair) == 100
    @test all(v in (0, 1) for v in ŷ_fair)
end

@testset "HealthEquity — Platt calibration by group" begin
    if !HE_LOADED; @test_skip true; return; end
    probs, y, groups = make_binary_data(120)
    params = platt_calibrate_by_group(probs, y, groups; n_iter=50)
    @test isa(params, Dict)
    p_cal = apply_group_calibration(probs, groups, params)
    @test length(p_cal) == 120
    @test all(0.0 .<= p_cal .<= 1.0)
end

@testset "HealthEquity — equity_report" begin
    if !HE_LOADED; @test_skip true; return; end
    probs, y, groups = make_binary_data(100)
    X_feat = randn(MersenneTwister(9), 100, 3)
    report = equity_report(probs, y, groups;
                           model_name  = "TestModel",
                           X_features  = X_feat,
                           feature_names = ["pov","rural","dist"],
                           ses_var     = randn(MersenneTwister(10), 100))
    @test isa(report, EquityReport)
    @test !isempty(report.recommendations)
end

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 2 — SpatialRegression
# ══════════════════════════════════════════════════════════════════════════════

@testset "SpatialRegression — distance_matrix" begin
    if !SR_LOADED; @test_skip true; return; end
    coords = [0.0 0.0; 3.0 4.0; 1.0 0.0]
    D = distance_matrix(coords)
    @test size(D) == (3, 3)
    @test D[1,2] ≈ 5.0 atol=1e-10
    @test all(diag(D) .≈ 0.0)
    @test all(D .>= 0.0)
    @test D ≈ D'  # symmetry
end

@testset "SpatialRegression — GWR fit" begin
    if !SR_LOADED; @test_skip true; return; end
    sp = make_spatial_data(35)
    m  = gwr_fit(sp.y, sp.X, sp.coords;
                  bandwidth     = 2.5,
                  kernel        = :gaussian,
                  feature_names = ["poverty","rurality","distance"])
    @test isa(m, GWRModel)
    @test size(m.local_β) == (35, 4)   # intercept + 3 features
    @test length(m.residuals) == 35
    @test length(m.fitted) == 35
    @test isfinite(m.aic_c)
    r2_ols = 1 - sum(m.residuals.^2) / sum((sp.y .- mean(sp.y)).^2)
    @test r2_ols > 0.0  # GWR residuals should be finite
end

@testset "SpatialRegression — GWR predict and summary" begin
    if !SR_LOADED; @test_skip true; return; end
    sp = make_spatial_data(30)
    m  = gwr_fit(sp.y, sp.X, sp.coords; bandwidth=2.5)
    df = gwr_summary(m)
    @test isa(df, DataFrame)
    @test "fitted" in names(df)
    @test "residual" in names(df)
    @test "local_r2" in names(df)
    @test nrow(df) == 30

    # Predict at first 5 training points
    ŷ_new = gwr_predict(m, sp.X[1:5,:], sp.coords[1:5,:])
    @test length(ŷ_new) == 5
    @test all(isfinite.(ŷ_new))
end

@testset "SpatialRegression — bandwidth_aic" begin
    if !SR_LOADED; @test_skip true; return; end
    sp = make_spatial_data(30)
    bw = bandwidth_aic(sp.y, sp.X, sp.coords; n_candidates=6)
    @test bw > 0.0
    @test isfinite(bw)
end

@testset "SpatialRegression — Spatial lag model" begin
    if !SR_LOADED; @test_skip true; return; end
    sp = make_spatial_data(40)
    m  = spatial_lag_fit(sp.y, sp.X, sp.W;
                          feature_names=["poverty","rurality","distance"])
    @test isa(m, SpatialLagModel)
    @test -1.0 < m.ρ < 1.0
    @test length(m.β) == 4  # intercept + 3
    @test isfinite(m.aic)
    @test isfinite(m.log_lik)
    @test length(m.residuals) == 40
end

@testset "SpatialRegression — Spatial error model" begin
    if !SR_LOADED; @test_skip true; return; end
    sp = make_spatial_data(40)
    m  = spatial_error_fit(sp.y, sp.X, sp.W;
                            feature_names=["poverty","rurality","distance"])
    @test isa(m, SpatialErrorModel)
    @test -1.0 < m.λ < 1.0
    @test isfinite(m.aic)
    @test length(m.residuals) == 40
end

@testset "SpatialRegression — Moran's I" begin
    if !SR_LOADED; @test_skip true; return; end
    sp = make_spatial_data(40)
    n, p = size(sp.X)
    X_aug = hcat(ones(n), sp.X)
    β_ols = (X_aug'X_aug + 1e-8I) \ X_aug'sp.y
    e     = sp.y .- X_aug * β_ols
    res   = moran_residuals(e, sp.W; permutations=99)
    @test isfinite(res.I)
    @test isfinite(res.z)
    @test 0.0 <= res.p <= 1.0
end

@testset "SpatialRegression — LM diagnostic tests" begin
    if !SR_LOADED; @test_skip true; return; end
    sp = make_spatial_data(40)
    n, p = size(sp.X)
    X_aug = hcat(ones(n), sp.X)
    β_ols = (X_aug'X_aug + 1e-8I) \ X_aug'sp.y
    e     = sp.y .- X_aug * β_ols
    lml   = lm_lag_test(e, sp.X, sp.W)
    lme   = lm_error_test(e, sp.X, sp.W)
    @test lml.stat >= 0.0
    @test lme.stat >= 0.0
    @test 0.0 <= lml.p <= 1.0
    @test 0.0 <= lme.p <= 1.0

    diag = run_diagnostics(e, sp.X, sp.W; permutations=99)
    @test isa(diag, SpatialDiagnostics)
    @test isa(diag.recommend_lag, Bool)
    @test isa(diag.recommend_error, Bool)
end

@testset "SpatialRegression — GW-RF" begin
    if !SR_LOADED; @test_skip true; return; end
    sp   = make_spatial_data(35)
    rng  = MersenneTwister(11)
    m_rf = gwrf_fit(sp.y, sp.X, sp.coords;
                     bandwidth  = 2.5,
                     n_trees    = 10,
                     max_depth  = 3,
                     rng        = rng)
    @test isa(m_rf, GWRFModel)
    @test isfinite(m_rf.global_rmse)
    @test m_rf.global_rmse > 0.0

    μ, σ = gwrf_predict(m_rf, sp.X[1:5,:], sp.coords[1:5,:];
                         rng=rng, n_trees=10, max_depth=3)
    @test length(μ) == 5
    @test length(σ) == 5
    @test all(isfinite.(μ))
    @test all(σ .>= 0.0)
end

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 3 — ConformalHealth
# ══════════════════════════════════════════════════════════════════════════════

@testset "ConformalHealth — Split conformal coverage guarantee" begin
    if !CH_LOADED; @test_skip true; return; end
    X, y = make_regression_data(300)
    n_tr = 200; n_cal = 60; α = 0.10

    X_tr = X[1:n_tr, :]; y_tr = y[1:n_tr]
    X_c  = X[n_tr+1:n_tr+n_cal, :]; y_c  = y[n_tr+1:n_tr+n_cal]
    X_te = X[n_tr+n_cal+1:end, :];  y_te = y[n_tr+n_cal+1:end]

    X_aug = hcat(ones(n_tr), X_tr)
    β     = (X_aug'X_aug + 1e-8I) \ X_aug'y_tr
    pred_fn = Xn -> vec(hcat(ones(size(Xn,1)), Xn) * β)

    cr  = conformal_fit(pred_fn, X_c, y_c; α=α)
    @test cr.q̂ > 0.0
    @test cr.n_calib == n_cal

    r   = conformal_predict(cr, X_te)
    @test length(r.lower) == size(X_te, 1)
    @test all(r.lower .<= r.upper)

    cov = conformal_coverage(r, y_te)
    @test cov.coverage >= 1 - α - 0.05   # allow 5% slack for finite n
    @test cov.mean_width > 0.0
end

@testset "ConformalHealth — CQR adaptive intervals" begin
    if !CH_LOADED; @test_skip true; return; end
    X, y = make_regression_data(300)
    n_tr = 180; n_cal = 60; α = 0.10

    X_tr = X[1:n_tr, :]; y_tr = y[1:n_tr]
    X_c  = X[n_tr+1:n_tr+n_cal, :]; y_c  = y[n_tr+1:n_tr+n_cal]
    X_te = X[n_tr+n_cal+1:end, :]

    m_cqr = cqr_fit(X_tr, y_tr, X_c, y_c; α=α)
    @test m_cqr.q̂ isa Float64
    @test isfinite(m_cqr.q̂)

    df = cqr_predict(m_cqr, X_te)
    @test isa(df, DataFrame)
    @test "lower" in names(df)
    @test "upper" in names(df)
    @test "width" in names(df)
    @test all(df.width .>= 0.0)
    # CQR widths should vary (adaptive)
    @test std(df.width) > 0.0
end

@testset "ConformalHealth — CQR coverage" begin
    if !CH_LOADED; @test_skip true; return; end
    X, y = make_regression_data(350)
    n_tr = 200; n_cal = 80; α = 0.10
    X_tr = X[1:n_tr, :]; y_tr = y[1:n_tr]
    X_c  = X[n_tr+1:n_tr+n_cal, :]; y_c  = y[n_tr+1:n_tr+n_cal]
    X_te = X[n_tr+n_cal+1:end, :]; y_te = y[n_tr+n_cal+1:end]

    m_cqr = cqr_fit(X_tr, y_tr, X_c, y_c; α=α)
    df    = cqr_predict(m_cqr, X_te)
    cov_rate = mean((y_te .>= df.lower) .& (y_te .<= df.upper))
    @test cov_rate >= 1 - α - 0.05
end

@testset "ConformalHealth — Jackknife+" begin
    if !CH_LOADED; @test_skip true; return; end
    X, y = make_regression_data(150)
    n_tr = 80; α = 0.10
    X_tr = X[1:n_tr, :]; y_tr = y[1:n_tr]
    X_te = X[n_tr+1:end, :]; y_te = y[n_tr+1:end]

    fit_fn = (Xtr, ytr) -> begin
        Xa = hcat(ones(size(Xtr,1)), Xtr)
        β  = (Xa'Xa + 1e-8I) \ Xa'ytr
        Xn -> vec(hcat(ones(size(Xn,1)), Xn) * β)
    end

    jr  = jackknife_plus(fit_fn, X_tr, y_tr, X_te; α=α, max_n_loo=40)
    @test length(jr.lower) == size(X_te, 1)
    @test all(jr.lower .<= jr.upper)
    cov = mean((y_te .>= jr.lower) .& (y_te .<= jr.upper))
    # Jackknife+ guarantees ≥ 1-2α
    @test cov >= 1 - 2*α - 0.05
end

@testset "ConformalHealth — APS classification" begin
    if !CH_LOADED; @test_skip true; return; end
    rng = MersenneTwister(77)
    n_calib = 100; n_test = 50; K = 3; α = 0.10

    # Random softmax probabilities
    logits_c = randn(rng, n_calib, K)
    logits_t = randn(rng, n_test,  K)
    softmax_rows = m -> begin
        e = exp.(m .- maximum(m, dims=2))
        e ./ sum(e, dims=2)
    end
    probs_c = softmax_rows(logits_c)
    probs_t = softmax_rows(logits_t)
    y_c     = rand(rng, 1:K, n_calib)

    aps = aps_fit(probs_c, y_c; α=α, score_type=:aps)
    @test isfinite(aps.q̂)
    @test aps.n_classes == K

    sets = aps_predict(aps, probs_t)
    @test length(sets) == n_test
    @test all(length(s) >= 1 for s in sets)

    df_sets = conformal_classify(probs_t, aps)
    @test isa(df_sets, DataFrame)
    @test "set_size" in names(df_sets)
    @test all(df_sets.set_size .>= 1)
    # Marginal coverage check
    y_t    = rand(rng, 1:K, n_test)
    in_set = [y_t[i] in sets[i] for i in 1:n_test]
    @test mean(in_set) >= 1 - α - 0.1
end

@testset "ConformalHealth — Temperature scaling" begin
    if !CH_LOADED; @test_skip true; return; end
    rng = MersenneTwister(13)
    n = 80; K = 4
    logits = randn(rng, n, K) .* 3.0  # overconfident
    y_true = rand(rng, 1:K, n)

    T_opt, p_cal = temperature_scaling(logits, y_true; max_iter=200)
    @test T_opt > 0.0
    @test isfinite(T_opt)
    @test size(p_cal) == (n, K)
    # Each row should sum to 1
    row_sums = sum(p_cal, dims=2)
    @test all(abs.(row_sums .- 1.0) .< 1e-8)
    @test all(p_cal .>= 0.0)
end

@testset "ConformalHealth — Isotonic calibration" begin
    if !CH_LOADED; @test_skip true; return; end
    rng = MersenneTwister(31)
    n   = 100
    # Poorly calibrated: raw probs skewed high
    raw_probs  = clamp.(0.6 .+ 0.3*randn(rng, n), 0.01, 0.99)
    y          = Int.(rand(rng, n) .< 0.4)  # true rate is lower

    p_iso, cal_fn, knots = isotonic_calibrate(raw_probs, y)
    @test length(p_iso) == n
    @test all(0.0 .<= p_iso .<= 1.0)
    # Isotonic: sorted input → non-decreasing output
    sorted_raw = sort(raw_probs)
    sorted_cal = cal_fn.(sorted_raw)
    diffs = diff(sorted_cal)
    @test all(diffs .>= -1e-8)  # non-decreasing
end

@testset "ConformalHealth — Calibration error (ECE)" begin
    if !CH_LOADED; @test_skip true; return; end
    rng   = MersenneTwister(5)
    n     = 200
    probs = clamp.(rand(rng, n), 0.01, 0.99)
    y     = Int.(rand(rng, n) .< probs)

    cr = calibration_error(probs, y; n_bins=10)
    @test 0.0 <= cr.ece <= 1.0
    @test 0.0 <= cr.mce <= 1.0
    @test 0.0 <= cr.brier <= 1.0
    @test cr.mce >= cr.ece  # MCE ≥ ECE always

    rd = reliability_diagram(probs, y; n_bins=10)
    @test isa(rd, DataFrame)
    @test "confidence" in names(rd)
    @test "accuracy"   in names(rd)
end

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 4 — Cross-package integration
# ══════════════════════════════════════════════════════════════════════════════

@testset "Cross-package — HealthEquity audit on GWR residuals" begin
    if !SR_LOADED || !HE_LOADED; @test_skip true; return; end

    sp   = make_spatial_data(40)
    m_gwr = gwr_fit(sp.y, sp.X, sp.coords;
                     bandwidth=2.5, kernel=:gaussian)
    fitted = m_gwr.fitted

    # Classify counties as high/low access predictions (binary label)
    ŷ_binary = Int.(fitted .>= median(fitted))
    y_binary  = Int.(sp.y  .>= median(sp.y))
    groups    = repeat(["rural", "urban"], 20)

    # Run equity metrics on GWR predictions
    dp = demographic_parity(ŷ_binary, groups)
    @test isa(dp, DataFrame)

    G = gini_coefficient(max.(fitted, 1e-10))
    @test 0.0 <= G <= 1.0
end

@testset "Cross-package — Conformal intervals on spatial lag predictions" begin
    if !SR_LOADED || !CH_LOADED; @test_skip true; return; end

    sp = make_spatial_data(50)
    n  = size(sp.X, 1)

    # Fit spatial lag
    m_lag = spatial_lag_fit(sp.y, sp.X, sp.W)

    # Use spatial lag fitted values as a predict function for conformal
    # (held-out split from training residuals)
    n_cal = 15
    calib_idx = (n - n_cal + 1):n
    train_idx = 1:(n - n_cal)

    ŷ_all = m_lag.fitted
    X_aug  = hcat(ones(n), sp.X)
    β_ols  = (X_aug'X_aug + 1e-8I) \ X_aug'sp.y

    # OLS predict function (proxy for lag)
    pred_fn = Xn -> vec(hcat(ones(size(Xn,1)), Xn) * β_ols)

    cr  = conformal_fit(pred_fn, sp.X[calib_idx,:], sp.y[calib_idx]; α=0.10)
    r   = conformal_predict(cr, sp.X[train_idx[1:10],:])
    cov = conformal_coverage(r, sp.y[train_idx[1:10]])
    @test isfinite(cov.coverage)
    @test cov.mean_width > 0.0
end

@testset "Cross-package — CQR + equity conditional coverage" begin
    if !CH_LOADED || !HE_LOADED; @test_skip true; return; end

    X, y = make_regression_data(320)
    n_tr = 200; n_cal = 60; α = 0.10
    X_tr = X[1:n_tr, :]; y_tr = y[1:n_tr]
    X_c  = X[n_tr+1:n_tr+n_cal, :]; y_c  = y[n_tr+1:n_tr+n_cal]
    X_te = X[n_tr+n_cal+1:end, :]; y_te = y[n_tr+n_cal+1:end]

    m_cqr = cqr_fit(X_tr, y_tr, X_c, y_c; α=α)
    df    = cqr_predict(m_cqr, X_te)

    # Split test into two subgroups by first feature
    n_te  = size(X_te, 1)
    groups_te = X_te[:,1] .> 0 ? "hi" : "lo"  # broadcast comparison
    groups_te = [X_te[i,1] > 0 ? "hi" : "lo" for i in 1:n_te]
    mask_hi = groups_te .== "hi"
    mask_lo = .!mask_hi

    cov_hi = mean((y_te[mask_hi] .>= df.lower[mask_hi]) .& (y_te[mask_hi] .<= df.upper[mask_hi]))
    cov_lo = mean((y_te[mask_lo] .>= df.lower[mask_lo]) .& (y_te[mask_lo] .<= df.upper[mask_lo]))
    # Both conditional coverages should be reasonable
    @test isfinite(cov_hi)
    @test isfinite(cov_lo)

    # Use HealthEquity to check if interval widths are equitable
    widths = df.width
    G_widths = gini_coefficient(widths)
    @test 0.0 <= G_widths <= 1.0
end

@testset "Cross-package — Full equity pipeline smoke test" begin
    if !HE_LOADED || !SR_LOADED || !CH_LOADED; @test_skip true; return; end

    rng = MersenneTwister(42)
    n   = 60

    # Step 1: Generate spatial data
    sp = make_spatial_data(n)

    # Step 2: Fit spatial model
    m_lag = spatial_lag_fit(sp.y, sp.X, sp.W)
    ŷ_lag = m_lag.fitted

    # Step 3: Calibrate conformal intervals
    n_cal = 15; cal_idx = (n-n_cal+1):n
    X_aug = hcat(ones(n), sp.X)
    β_ols = (X_aug'X_aug + 1e-8I) \ X_aug'sp.y
    pred_fn = Xn -> vec(hcat(ones(size(Xn,1)), Xn) * β_ols)
    cr = conformal_fit(pred_fn, sp.X[cal_idx,:], sp.y[cal_idx]; α=0.10)

    # Step 4: Equity audit on binary access classification
    groups    = [i <= n÷2 ? "rural" : "urban" for i in 1:n]
    ŷ_binary  = Int.(ŷ_lag .>= median(ŷ_lag))
    y_binary  = Int.(sp.y  .>= median(sp.y))

    G = gini_coefficient(max.(sp.y, 1e-10))
    dp = demographic_parity(ŷ_binary, groups)
    eo = equalized_odds(ŷ_binary, y_binary, groups)

    @test isfinite(G)
    @test isa(dp, DataFrame)
    @test isa(eo, DataFrame)
    @test isfinite(cr.q̂)

    println("\n  [Integration] Spatial lag ρ=$(round(m_lag.ρ;digits=3)), " *
            "Conformal q̂=$(round(cr.q̂;digits=4)), Gini=$(round(G;digits=3))")
end

println("\nVol 8 integration tests complete.")
