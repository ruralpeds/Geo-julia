#!/usr/bin/env julia
# test/runtests.jl — DeepHealth.jl unit tests
# Chapter 45 — Open-Source Healthcare GIS Textbook in Julia

using Test, Random, LinearAlgebra, Statistics
using DeepHealth

Random.seed!(42)

@testset "DeepHealth.jl" begin

    # ── Layer tests ───────────────────────────────────────────────────────────

    @testset "Dense — forward shape and values" begin
        l = Dense(4, 8; activation=:relu)
        x = randn(4, 10)
        y = forward(l, x)
        @test size(y) == (8, 10)
        @test all(y .>= 0)  # ReLU non-negative
    end

    @testset "Dense — sigmoid output in (0,1)" begin
        l = Dense(3, 1; activation=:sigmoid, init=:glorot)
        x = randn(3, 20)
        y = forward(l, x)
        @test all(0 .< y .< 1)
    end

    @testset "BatchNorm — zero mean, unit var in training" begin
        bn = BatchNorm(4)
        x  = randn(4, 32) .* 5 .+ 3
        y  = forward_train(bn, x)
        @test all(abs.(vec(mean(y; dims=2))) .< 1.0)
    end

    @testset "Dropout — zero fraction in [p-0.2, p+0.2] training" begin
        d   = Dropout(0.5)
        rng = MersenneTwister(1)
        x   = ones(100, 1)
        y   = forward_train(d, x; rng=rng)
        frac_zero = mean(y .== 0)
        @test 0.3 <= frac_zero <= 0.7
    end

    @testset "Dropout — identity at inference" begin
        d = Dropout(0.8)
        x = randn(50)
        @test forward(d, x) === x
    end

    @testset "MultiHeadAttention — output shape preserved" begin
        mha = MultiHeadAttention(16, 4)
        x   = randn(16, 10)
        y   = forward(mha, x)
        @test size(y) == (16, 10)
    end

    # ── Network tests ─────────────────────────────────────────────────────────

    @testset "MLP — build and forward pass" begin
        net = build_mlp(8, [32, 16], 1)
        x   = randn(8, 20)
        y   = forward(net, x)
        @test size(y) == (1, 20)
        @test !any(isnan, y)
    end

    @testset "MLP — n_params positive" begin
        net = build_mlp(5, [20, 10], 2)
        @test n_params(net) > 0
    end

    @testset "GNN — message passing shape" begin
        gnn = build_gnn(4, [8], 2)
        H   = randn(4, 6)         # 4 features, 6 nodes
        A   = Float64.(rand(6,6) .> 0.5)
        out = forward(gnn, H, A)
        @test size(out) == (2, 6)
        @test !any(isnan, out)
    end

    @testset "TabNetBlock — output finite" begin
        tb = TabNetBlock(8, 4; n_steps=2)
        x  = randn(8, 12)
        y  = forward(tb, x)
        @test size(y) == (4, 12)
        @test !any(isnan, y)
    end

    @testset "ResidualBlock — output shape" begin
        rb = ResidualBlock(8, 8)
        x  = randn(8, 5)
        y  = forward(rb, x)
        @test size(y) == (8, 5)
    end

    # ── Training tests ────────────────────────────────────────────────────────

    @testset "Adam — loss decreases on simple regression" begin
        rng = MersenneTwister(7)
        n = 50; p = 4
        X = randn(rng, p, n)
        y = vec(sum(X; dims=1)) .* 0.5 .+ randn(rng, n) .* 0.1
        net = build_mlp(p, [16, 8], 1)
        hist = train!(net, X, reshape(y, 1, :);
                      n_epochs=50, batch_size=16, lr=1e-2, rng=rng)
        @test last(hist.train_loss) < first(hist.train_loss)
    end

    @testset "EarlyStoppingCallback — fires within patience" begin
        cb = EarlyStoppingCallback(; patience=3)
        for i in 1:5
            update!(cb, 1.0, i)   # non-improving loss
        end
        @test cb.should_stop
    end

    @testset "CosineSchedule — decreases then increases" begin
        s = CosineSchedule(1e-2, 1e-4, 100)
        lr1 = lr_at(s, 1)
        lr50 = lr_at(s, 50)
        lr100 = lr_at(s, 100)
        @test lr1 > lr50 > lr100
        @test lr100 ≈ 1e-4 atol=1e-5
    end

    @testset "minibatch_iter — all samples covered" begin
        X = randn(3, 100); y = randn(100)
        batches = minibatch_iter(X, y, 32; shuffle=false)
        total = sum(size(b[1], 2) for b in batches)
        @test total == 100
    end

    # ── Health model tests ────────────────────────────────────────────────────

    @testset "AccessPredictor — predictions finite" begin
        rng = MersenneTwister(13)
        X = randn(rng, 6, 80)
        y = randn(rng, 80) .* 0.01 .+ 0.005
        ap = AccessPredictor(6; hidden=[16, 8])
        ap2 = fit!(ap, X, y; n_epochs=20, batch_size=16, rng=rng)
        ŷ = predict_access(ap2, X[:, 1:5])
        @test length(ŷ) == 5
        @test !any(isnan, ŷ)
    end

    @testset "ReadmissionRisk — probabilities in (0,1)" begin
        rng = MersenneTwister(21)
        X = randn(rng, 8, 100)
        y = rand(rng, [0, 1], 100)
        rr = ReadmissionRisk(8; hidden=[16, 8])
        rr2 = fit!(rr, X, Float64.(y); n_epochs=20, batch_size=32, rng=rng)
        probs, labels = predict_readmission(rr2, X[:, 1:10])
        @test length(probs) == 10
        @test all(0 .<= probs .<= 1)
        @test all(labels .∈ [[0, 1]])
    end

    @testset "SepsisAlert — severity levels valid" begin
        sa = SepsisAlert(11)
        sa.μ .= 0.0; sa.σ .= 1.0
        X = hcat([sofa_features() for _ in 1:5]...)
        scores, alerts, sev = alert_sepsis(sa, X)
        @test length(scores) == 5
        @test all(0 .<= scores .<= 1)
        @test all(s ∈ (:low, :moderate, :high, :critical) for s in sev)
    end

    @testset "sofa_features — correct dimension" begin
        f = sofa_features()
        @test length(f) == 11
        @test !any(isnan, f)
    end

    # ── Report tests ──────────────────────────────────────────────────────────

    @testset "DeepHealthReport — generates successfully" begin
        rng = MersenneTwister(99)
        X = randn(rng, 4, 40)
        y = randn(rng, 40)
        net = build_mlp(4, [8], 1)
        train!(net, X, reshape(y, 1, :); n_epochs=10, batch_size=16, rng=rng)
        rpt = deep_health_report(net, X, y; task=:regression, n_perm=5, rng=rng)
        @test rpt.n_params > 0
        @test length(rpt.importance) == 4
        @test all(0 .<= rpt.importance .<= 1)
    end

    @testset "training_summary — returns DataFrame" begin
        hist = TrainingHistory([0.5, 0.4, 0.3], [0.55, 0.45], 3, 3, 1e-3)
        df = training_summary(hist)
        @test nrow(df) == 3
        @test hasproperty(df, :epoch)
        @test hasproperty(df, :train_loss)
    end

end  # @testset
