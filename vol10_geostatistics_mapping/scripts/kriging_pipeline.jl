#!/usr/bin/env julia
# scripts/kriging_pipeline.jl
# Geostatistical analysis of ND county healthcare access scores

using Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "packages", "GeostatHealth", "src", "GeostatHealth.jl"))
using .GeostatHealth

println("=" ^ 65)
println("  Vol 10 — Geostatistical Analysis: Kriging Healthcare Access")
println("  North Dakota County-Level Access Score Interpolation")
println("=" ^ 65)

# ── Simulated ND county access data ──────────────────────────────────────────

function make_nd_access_data(n=53; seed=42)
    rng    = MersenneTwister(seed)
    # ND bounding box: lat 45.9-49.0 N, lon -104.1 to -96.5 W
    lats   = 45.9 .+ 3.1 .* rand(rng, n)
    lons   = -104.1 .+ 7.6 .* rand(rng, n)
    coords = hcat(lons, lats)  # (x=lon, y=lat)

    # True spatial access surface: east higher than west (proximity to Fargo)
    true_access = 0.35 .+ 0.15 .* (lons .+ 104.1) ./ 7.6 .-
                  0.1 .* abs.(lats .- 47.5) ./ 1.5 .+
                  0.1 .* randn(rng, n)
    true_access = clamp.(true_access, 0.01, 0.99)

    # Hold out 10 points for validation
    val_idx   = randperm(rng, n)[1:10]
    train_idx = setdiff(1:n, val_idx)

    (coords=coords, z=true_access, lats=lats, lons=lons,
     train_idx=train_idx, val_idx=val_idx, n=n)
end

data = make_nd_access_data()
println("\n► N=$(data.n) counties  ($(length(data.train_idx)) train, $(length(data.val_idx)) validation)")

# ── Section 1: Empirical variogram ───────────────────────────────────────────

println("\n[1] Empirical Variogram")
coords_tr = data.coords[data.train_idx, :]
z_tr      = data.z[data.train_idx]

ev_cl = empirical_variogram(coords_tr, z_tr; n_lags=12, estimator=:classical)
ev_rb = empirical_variogram(coords_tr, z_tr; n_lags=12, estimator=:robust)
valid = .!isnan.(ev_cl.gamma)
println("  Valid lag bins: $(sum(valid))")
println("  Lag [1]: h=$(round(ev_cl.lags[1],digits=3))  γ=$(round(ev_cl.gamma[1],digits=5))")
println("  Max γ (classical): $(round(maximum(ev_cl.gamma[valid]),digits=5))")
println("  Max γ (robust):    $(round(maximum(ev_rb.gamma[valid]),digits=5))")

# ── Section 2: Variogram model fitting ───────────────────────────────────────

println("\n[2] Variogram Model Fitting")
vm_sph = fit_variogram(ev_cl; model=:spherical)
vm_exp = fit_variogram(ev_cl; model=:exponential)
vm_gau = fit_variogram(ev_cl; model=:gaussian)

for (name, vm) in [("Spherical", vm_sph), ("Exponential", vm_exp), ("Gaussian", vm_gau)]
    vs = variogram_summary(vm)
    println("  $(rpad(name,12)) nugget=$(round(vm.nugget,digits=5))  " *
            "sill=$(round(vm.sill,digits=5))  range=$(round(vm.range,digits=4))  " *
            "nugget/sill=$(round(100*vs.nugget_ratio,digits=1))%")
end

# Use spherical (common in geostatistics)
vm = vm_sph

# ── Section 3: Ordinary kriging ──────────────────────────────────────────────

println("\n[3] Ordinary Kriging Prediction")
ok = ordinary_kriging(z_tr, coords_tr, vm)

# Predict at validation locations
coords_val = data.coords[data.val_idx, :]
z_val      = data.z[data.val_idx]
ẑ_ok, σ²_ok = ok_predict(ok, coords_val)

rmse_ok = sqrt(mean((ẑ_ok .- z_val).^2))
mae_ok  = mean(abs.(ẑ_ok .- z_val))
picp    = mean(abs.(ẑ_ok .- z_val) .<= 1.96 .* sqrt.(max.(σ²_ok, 0.0)))
println("  Validation RMSE: $(round(rmse_ok,digits=5))")
println("  Validation MAE:  $(round(mae_ok, digits=5))")
println("  95% PI coverage: $(round(100*picp,digits=1))%")
println("  Mean kriging SE: $(round(mean(sqrt.(max.(σ²_ok,0))),digits=5))")

# ── Section 4: Universal kriging (with longitude trend) ──────────────────────

println("\n[4] Universal Kriging (linear E-W trend)")
uk  = universal_kriging(z_tr, coords_tr, vm; degree=1)
ẑ_uk, σ²_uk = uk_predict(uk, coords_val)
rmse_uk = sqrt(mean((ẑ_uk .- z_val).^2))
println("  UK Validation RMSE: $(round(rmse_uk,digits=5))")
println("  Best model: $(rmse_uk < rmse_ok ? "Universal" : "Ordinary") kriging")

# ── Section 5: Leave-one-out CV ───────────────────────────────────────────────

println("\n[5] Leave-One-Out Cross-Validation")
loo = kriging_loo_cv(z_tr, coords_tr, vm; method=:ordinary)
println("  LOO RMSE:       $(round(loo.rmse, digits=5))")
println("  LOO MAE:        $(round(loo.mae,  digits=5))")
println("  LOO mean bias:  $(round(loo.mean_bias, digits=6))")
println("  LOO 95% PI cov: $(round(100*loo.picp_95, digits=1))%")

# ── Section 6: Sequential Gaussian Simulation ─────────────────────────────────

println("\n[6] Sequential Gaussian Simulation (5 realisations)")
rng      = MersenneTwister(7)
pred_lons = range(-104.0, -97.0, length=8)
pred_lats = range(46.0, 49.0, length=8)
pred_c   = hcat([x for x in pred_lons for _ in pred_lats],
                 [y for _ in pred_lons for y in pred_lats])

sims = sgs_simulate(z_tr, coords_tr, pred_c, vm; n_real=5, rng=rng)
unc  = sgs_uncertainty(sims)
println("  Simulated at $(size(pred_c,1)) grid points")
println("  Mean: $(round(mean(unc.mean), digits=4))  " *
        "Variance: $(round(mean(unc.variance), digits=6))")
println("  90% PI width (mean): $(round(mean(unc.upper_90 .- unc.lower_90), digits=4))")

# ── Section 7: Full report ────────────────────────────────────────────────────

println("\n[7] Geostat Report")
report = geostat_report(z_tr, coords_tr; series_name="ND-Access-Score")
print_geostat_report(report)

println("\n✓ Kriging pipeline complete.")
