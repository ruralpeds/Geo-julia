using Test
using Random

# Test that all volume packages load and their core functions work together

@testset "Unified Integration Tests" begin
    rng = MersenneTwister(42)

    @testset "Vol 13: InfectiousDisease" begin
        r = sir(10000, 10, 0.3, 0.1; t_end=100.0, dt=1.0)
        @test r isa SIRResult
        @test length(r.S) > 50
        @test all(abs.(r.S .+ r.I .+ r.R .- 1.0) .< 0.01)
        @test r0_from_params(0.3, 0.1) ≈ 3.0
        @test herd_immunity_threshold(3.0) ≈ 2/3 atol=0.01
    end

    @testset "Vol 13: SurveillanceSystems" begin
        x = vcat(fill(10.0, 30), fill(25.0, 20))
        c = cusum(x; μ₀=10.0, σ₀=3.0, k=1.0, h=5.0)
        @test c isa CUSUMResult
        @test any(c.alerts)
        e = ewma(x; λ=0.2, L=2.7, μ₀=10.0, σ₀=3.0)
        @test e isa EWMAResult
    end

    @testset "Vol 13: HealthIntelligence" begin
        X = randn(rng, 20, 3)
        r = composite_risk_score(X; n_bands=4)
        @test r isa RiskScoreResult
        @test length(r.bands) == 20
        @test all(1 .<= r.bands .<= 4)
    end

    @testset "Vol 10: GeostatHealth" begin
        coords = rand(rng, 30, 2) * 100
        z = [sin(coords[i,1]/20) + randn(rng)*0.1 for i in 1:30]
        ev = empirical_variogram(coords, z; n_lags=10)
        @test ev isa EmpiricalVariogram
        vm = fit_variogram(ev; model=:spherical)
        @test vm isa VariogramModel
        @test vm.sill > 0
        ok = ordinary_kriging(z, coords, vm)
        @test ok isa OrdinaryKrigingResult
        new_pts = rand(rng, 5, 2) * 100
        preds, vars = ok_predict(ok, new_pts)
        @test length(preds) == 5
        @test all(vars .>= 0)
    end

    @testset "Vol 10: DiseaseMapping" begin
        obs = rand(rng, 10:30, 20)
        exp_cases = fill(20, 20)
        results = batch_smr(obs, exp_cases)
        @test length(results) == 20
        @test all(r.smr > 0 for r in results)
        eb = eb_smooth(obs, exp_cases)
        @test eb isa EBSmoothedResult
        @test length(eb.smoothed) == 20
    end

    @testset "Vol 9: SurvivalAnalysis" begin
        times = sort(rand(rng, 50) * 100)
        status = rand(rng, [0, 1], 50)
        km = kaplan_meier(times, status)
        @test km isa KMResult
        @test km.survival[1] <= 1.0
        @test all(diff(km.survival) .<= 0)  # non-increasing

        X = randn(rng, 50, 3)
        cox = cox_fit(times, status, X)
        @test cox isa CoxModel
        @test length(cox.β) == 3
    end

    @testset "Vol 9: TimeSeriesHealth" begin
        y = cumsum(randn(rng, 100)) .+ 50
        model = auto_arima(y; max_p=2, max_q=2)
        @test model isa ARIMAModel
        @test model.p >= 0
        @test model.q >= 0
        @test isfinite(model.aic)
    end

    @testset "Vol 11: CausalInference" begin
        n = 100
        X = randn(rng, n, 3)
        D = Float64.(rand(rng, n) .> 0.5)
        y = 2.0 .* D .+ X * [1.0, 0.5, -0.3] .+ randn(rng, n)
        ps_model = ps_fit(D, X)
        @test ps_model isa PropensityModel
        ps = ps_predict(ps_model, X)
        @test all(0 .< ps .< 1)
        ipw_result = ipw_ate(D, y, ps; n_boot=50, rng=rng)
        @test ipw_result isa IPWResult
        @test abs(ipw_result.estimate - 2.0) < 1.5  # rough check
    end

    @testset "Vol 11: PolicyEval" begin
        n = 80
        y = vcat(randn(rng, n), randn(rng, n) .+ 1.5 .* vcat(ones(n÷2), zeros(n÷2)))
        treat = vcat(vcat(ones(n÷2), zeros(n÷2)), vcat(ones(n÷2), zeros(n÷2)))
        post = vcat(zeros(n), ones(n))
        did = did_2x2(y, treat, post; n_boot=100, rng=rng)
        @test did isa DIDResult
        @test abs(did.att - 1.5) < 1.0
    end

    @testset "Vol 12: FacilityLocation" begin
        demand = rand(rng, 15, 2) * 50
        candidates = rand(rng, 8, 2) * 50
        result = p_median(demand, candidates, 3; rng=rng)
        @test result isa PMedianResult
        @test length(result.open_facilities) == 3
        @test p_median_obj(result) > 0
    end

    @testset "Vol 12: ResourceAllocation" begin
        R = rand(rng, 4, 3) * 10  # 4 states, 3 actions
        P = zeros(4, 4, 3)
        for a in 1:3
            for s in 1:4
                P[s, :, a] = rand(rng, 4)
                P[s, :, a] ./= sum(P[s, :, a])
            end
        end
        mdp = value_iteration(R, P, 0.95)
        @test mdp isa MDPResult
        @test length(mdp.policy) == 4
        @test all(1 .<= mdp.policy .<= 3)
    end

    @testset "Cross-Volume Composition" begin
        # Pipeline: Epidemic → Surveillance → Spatial → Policy
        sir_r = sir(100000, 10, 0.3, 0.1; t_end=200.0, dt=1.0)
        @test sir_r.S[end] < 0.1  # most infected

        incidence = diff(sir_r.I) .* 100000
        daily_cases = max.(round.(Int, abs.(incidence[1:min(150, length(incidence))])), 0)
        daily_float = Float64.(daily_cases)

        cusum_r = cusum(daily_float; μ₀=mean(daily_float[1:10]),
                        σ₀=std(daily_float[1:10]) + 1.0, k=1.0, h=4.0)
        @test cusum_r isa CUSUMResult

        if length(daily_float) >= 30
            arima_r = auto_arima(daily_float[1:min(100, length(daily_float))]; max_p=2, max_q=2)
            @test arima_r isa ARIMAModel
        end
    end
end

println("\n✓ All unified integration tests passed!")
