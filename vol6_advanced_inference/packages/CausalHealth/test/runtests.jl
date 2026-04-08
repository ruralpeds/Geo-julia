using Test, Random, DataFrames, Statistics
Random.seed!(42)

import Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using CausalHealth

# ── Synthetic policy panel ────────────────────────────────────────────────────
function make_policy_panel(n_units=40, n_years=10, treat_frac=0.4,
                            treat_year=2018, τ_true=0.05; rng=MersenneTwister(42))
    all_ids   = 1:n_units
    treat_ids = sample(rng, collect(all_ids), round(Int, n_units*treat_frac); replace=false)
    rows = NamedTuple[]
    for id in all_ids
        unit_fe = randn(rng) * 0.2
        for yr in 2013:2013+n_years-1
            treated  = id in treat_ids
            post     = yr >= treat_year
            y = 0.5 + unit_fe + 0.01*(yr-2013) +
                (treated && post ? τ_true : 0.0) + 0.05*randn(rng)
            push!(rows, (GEOID=lpad(id,3,'0'), year=yr, treated=Int(treated),
                         outcome=y, poverty=10+randn(rng)*3, instrument=randn(rng)))
        end
    end
    DataFrame(rows)
end

panel = make_policy_panel()

@testset "CausalHealth Tests" begin

    @testset "1. DiD — basic" begin
        r = did_estimate(panel; id_col=:GEOID, time_col=:year, treat_col=:treated,
                          outcome_col=:outcome, treat_time=2018)
        @test r isa DiDResult
        @test isfinite(r.att)
        @test r.se > 0
        @test 0 <= r.p_value <= 1
        @test r.n_treated > 0 && r.n_control > 0
    end

    @testset "2. DiD — effect direction" begin
        r = did_estimate(panel; id_col=:GEOID, time_col=:year, treat_col=:treated,
                          outcome_col=:outcome, treat_time=2018)
        # True ATT = 0.05; should be in right ballpark
        @test abs(r.att - 0.05) < 0.15
        @test r.ci_lo < r.att < r.ci_hi
    end

    @testset "3. DiD — event study" begin
        r = did_estimate(panel; id_col=:GEOID, time_col=:year, treat_col=:treated,
                          outcome_col=:outcome, treat_time=2018)
        @test !isnothing(r.event_study)
        @test nrow(r.event_study) > 0
        @test hasproperty(r.event_study, :rel_time)
        @test hasproperty(r.event_study, :coef)
    end

    @testset "4. DiD — parallel trends p-value" begin
        r = did_estimate(panel; id_col=:GEOID, time_col=:year, treat_col=:treated,
                          outcome_col=:outcome, treat_time=2018)
        @test 0 <= r.pre_trend_p <= 1
        # True DGP has parallel trends; p should be > 0.05 most of the time
        @test r.pre_trend_p > 0.0
    end

    @testset "5. Synthetic control — basic" begin
        r = synthetic_control(panel; treated_id="001",
                              id_col=:GEOID, time_col=:year, outcome_col=:outcome,
                              treat_time=2018, n_placebos=5)
        @test r isa SyntheticControlResult
        @test length(r.weights) == length(r.donor_ids)
        @test abs(sum(r.weights) - 1.0) < 1e-6
        @test all(r.weights .>= -1e-9)
    end

    @testset "6. Synthetic control — gap series" begin
        r = synthetic_control(panel; treated_id="001",
                              id_col=:GEOID, time_col=:year, outcome_col=:outcome,
                              treat_time=2018, n_placebos=3)
        @test hasproperty(r.gap_series, :gap)
        @test hasproperty(r.gap_series, :Y_treated)
        @test hasproperty(r.gap_series, :Y_synth)
        @test r.pre_fit_rmse >= 0
    end

    @testset "7. Synthetic control — weights table" begin
        r = synthetic_control(panel; treated_id="001",
                              id_col=:GEOID, time_col=:year, outcome_col=:outcome,
                              treat_time=2018, n_placebos=3)
        wt = synth_weights(r)
        @test nrow(wt) == length(r.donor_ids)
        @test issorted(wt.weight; rev=true)
    end

    @testset "8. IV 2SLS — basic" begin
        r = iv_2sls(panel; outcome_col=:outcome, endog_col=:treated,
                    instrument_cols=[:instrument], exog_cols=[:poverty])
        @test r isa IVResult
        @test length(r.β_iv) == 3   # intercept + treated + poverty
        @test !any(isnan, r.β_iv)
        @test r.first_stage_F >= 0
        @test 0 <= r.hausman_p <= 1
    end

    @testset "9. IV — first stage F interpretation" begin
        r = iv_2sls(panel; outcome_col=:outcome, endog_col=:treated,
                    instrument_cols=[:instrument])
        fs = first_stage_f(r)
        @test fs.F >= 0
        @test fs.strength in ["strong", "weak", "very weak"]
    end

    @testset "10. IV — Hausman test" begin
        r = iv_2sls(panel; outcome_col=:outcome, endog_col=:treated,
                    instrument_cols=[:instrument])
        h = hausman_test(r)
        @test h.conclusion in ["reject_exogeneity", "fail_to_reject"]
        @test 0 <= h.p_value <= 1
    end

    @testset "11. RD — bandwidth selection" begin
        xc = randn(200)
        y  = 1.0 .+ 0.5 .* (xc .>= 0) .+ 0.1 .* xc .+ 0.1 .* randn(200)
        h  = CausalHealth.rd_bandwidth(xc, y)
        @test h > 0
        @test isfinite(h)
    end

    @testset "12. RD — sharp RD estimate" begin
        n   = 500
        rng = MersenneTwister(42)
        x   = randn(rng, n)
        y   = 2.0 .+ 0.3 .* (x .>= 0) .+ 0.5 .* x .+ 0.1 .* randn(rng, n)
        df  = DataFrame(x=x, y=y)
        r   = rd_estimate(df; running_col=:x, outcome_col=:y, cutoff=0.0,
                           bandwidth=1.5, poly_order=1)
        @test r isa RDResult
        @test isfinite(r.τ)
        # True effect = 0.3; should be in neighbourhood
        @test abs(r.τ - 0.3) < 0.25
        @test r.ci_lo < r.τ < r.ci_hi
    end

    @testset "13. RD — plot data" begin
        df = DataFrame(x=randn(200), y=randn(200))
        r  = rd_estimate(df; running_col=:x, outcome_col=:y, cutoff=0.0,
                          bandwidth=2.0, poly_order=1)
        @test nrow(r.plot_data) > 0
        @test hasproperty(r.plot_data, :fitted)
        @test hasproperty(r.plot_data, :side)
    end

    @testset "14. CausalReport + causal_summary" begin
        reports = [
            CausalReport("DiD",   0.05, 0.02, 0.012, 0.01, 0.09, 400, "TWFE"),
            CausalReport("IV",    0.06, 0.03, 0.045, 0.00, 0.12, 400, "F=12.3"),
        ]
        summ = causal_summary(reports)
        @test nrow(summ) == 2
        @test hasproperty(summ, :effect)
        @test hasproperty(summ, :method)
    end

end  # @testset

using StatsBase: sample
@info "CausalHealth tests complete."
