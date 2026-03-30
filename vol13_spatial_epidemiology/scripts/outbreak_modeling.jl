#!/usr/bin/env julia
# scripts/outbreak_modeling.jl
# Infectious disease modeling for North Dakota: SIR, SEIR, spatial spread, R₀

using Random, Statistics, Printf

include(joinpath(@__DIR__, "..", "packages", "InfectiousDisease", "src", "InfectiousDisease.jl"))
using .InfectiousDisease

rng = MersenneTwister(2024)

println("="^66)
println("  North Dakota Infectious Disease Modelling")
println("="^66)

# ── ND population context ─────────────────────────────────────────────────────
N_ND = 779_261   # 2023 ND population
# Influenza-like scenario: β=0.4, γ=1/4 (4-day infectious period)
β, γ = 0.4, 0.25

# ── SIR — deterministic ───────────────────────────────────────────────────────
println("\n── 1. Deterministic SIR (North Dakota Population) ──────────────────")
sir_det = sir(N_ND, 50, β, γ; t_end=200.0, dt=0.25)
@printf "  R₀ = %.2f  (β=%.2f, γ=%.2f)\n" sir_det.R₀ β γ
@printf "  Peak prevalence   : %.2f%%  at day %.0f\n" (sir_det.peak_I*100) sir_det.peak_t
@printf "  Final attack rate : %.1f%%  (%.0f individuals)\n" \
    (sir_det.attack_rate*100) (sir_det.attack_rate*N_ND)
@printf "  Herd immunity threshold: %.1f%%  of population\n" \
    (herd_immunity_threshold(sir_det.R₀)*100)

# ── SEIR — with latent period ─────────────────────────────────────────────────
println("\n── 2. SEIR Model (with 2-day incubation period) ────────────────────")
σ = 1/2  # σ = 1/incubation_period
seir_r = seir(N_ND, 100, 50, β, σ, γ; t_end=250.0, dt=0.25)
@printf "  R₀ = %.2f  (β=%.2f, σ=%.2f, γ=%.2f)\n" seir_r.R₀ β σ γ
@printf "  Peak exposed      : %.2f%%  at day %.0f\n" (maximum(seir_r.E)*100) seir_r.t[argmax(seir_r.E)]
@printf "  Peak infectious   : %.2f%%  at day %.0f\n" (seir_r.peak_I*100) seir_r.peak_t
@printf "  Final attack rate : %.1f%%\n" (seir_r.attack_rate*100)

# ── Stochastic SIR ────────────────────────────────────────────────────────────
println("\n── 3. Stochastic SIR (5 realisations) ──────────────────────────────")
for sim in 1:5
    rs = sir_stochastic(100_000, 5, β, γ; t_end=180.0, dt=1.0, rng=rng)
    @printf "    Sim %d: peak=%.2f%%  attack=%.1f%%\n" \
        sim (rs.peak_I*100) (rs.attack_rate*100)
end

# ── Spatial SIR — 5 ND region patches ────────────────────────────────────────
println("\n── 4. Spatial SIR (5 ND Regions) ───────────────────────────────────")
# Approximate ND 5-region coords (lon/lat simplified)
region_names  = ["Northwest","Northeast","Central","Southeast","Southwest"]
region_pop    = [65_000.0, 120_000.0, 80_000.0, 350_000.0, 164_261.0]
region_coords = [-103.8 48.0; -97.8 48.0; -100.5 47.0; -97.0 46.5; -103.0 46.5]
I₀_spatial    = [5.0, 0.0, 0.0, 0.0, 0.0]  # seed in Northwest

spat = spatial_sir(region_pop, I₀_spatial, region_coords, β, γ;
                    coupling_strength=0.02, gravity=true, t_end=200.0, dt=1.0)
@printf "  Global R₀ estimate: %.2f\n" spat.R₀_global
@printf "  Peak region: %s (patch %d)\n" region_names[spat.peak_patch] spat.peak_patch
println("  Attack rates by region:")
for (i, name) in enumerate(region_names)
    @printf "    %-12s : %5.1f%% (%d individuals)\n" \
        name (spat.attack_rate[i]*100) round(Int, spat.attack_rate[i]*region_pop[i])
end

# ── R₀ estimation methods ─────────────────────────────────────────────────────
println("\n── 5. R₀ Estimation Methods ─────────────────────────────────────────")
I_series = sir_det.I .* N_ND

est_growth = r0_from_growth(I_series; γ=γ, n_early=20)
est_attack = r0_from_sir(sir_det.S[end] * N_ND, N_ND)
est_params = r0_from_params(β, γ)

@printf "  True R₀           : %.3f\n" (β/γ)
@printf "  From growth rate  : %.3f  (95%% CI: %.3f–%.3f)\n" \
    est_growth.R₀ est_growth.ci_lower est_growth.ci_upper
@printf "  From attack rate  : %.3f\n" est_attack.R₀
@printf "  From parameters   : %.3f\n" est_params

# ── Serial interval and doubling time ─────────────────────────────────────────
println("\n── 6. Epidemic Timing Metrics ───────────────────────────────────────")
r = est_growth.r
@printf "  Growth rate r     : %.4f /day\n" r
@printf "  Doubling time     : %.1f days\n" doubling_time(r)
# Simulate serial interval distribution
si_samples = 4.0 .+ randn(rng, 200)  # mean SI ≈ 4 days
si_est = estimate_serial_interval(si_samples; n_boot=200, rng=rng)
@printf "  Serial interval   : %.2f days (SD=%.2f, 95%% CI: %.2f–%.2f)\n" \
    si_est.mean si_est.sd si_est.ci_lower si_est.ci_upper

# ── Vaccination scenarios ─────────────────────────────────────────────────────
println("\n── 7. Vaccination Scenario Analysis ─────────────────────────────────")
hit = herd_immunity_threshold(β/γ)
@printf "  Herd immunity threshold: %.1f%% coverage\n" (hit*100)
for p_vax in [0.0, 0.3, 0.5, 0.7, hit, 0.95]
    Re = effective_r0(β/γ, p_vax)
    ar = attack_rate_prediction(Re)
    @printf "    Vaccination %.0f%%: Rₑ=%.2f  predicted attack rate=%.1f%%\n" \
        (p_vax*100) Re (ar*100)
end

println("\n" * "="^66)
println("  Outbreak modelling complete.")
println("="^66)
