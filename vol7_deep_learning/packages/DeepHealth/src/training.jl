# training.jl — Optimizers, training loops, and learning rate schedules
# Chapter 45 — Open-Source Healthcare GIS Textbook in Julia

# ── Optimizer state ───────────────────────────────────────────────────────────

"""
    AdamOptimizer

Adaptive moment estimation (Kingma & Ba 2014).
m_t = β₁·m_{t-1} + (1-β₁)·g
v_t = β₂·v_{t-1} + (1-β₂)·g²
θ_t = θ_{t-1} - α·m̂_t / (√v̂_t + ε)
"""
mutable struct AdamOptimizer
    lr    :: Float64
    β1    :: Float64
    β2    :: Float64
    ε     :: Float64
    t     :: Int               # step counter (for bias correction)
    state :: Dict{String, Any} # m and v per parameter tensor
end

AdamOptimizer(; lr=1e-3, β1=0.9, β2=0.999, ε=1e-8) =
    AdamOptimizer(lr, β1, β2, ε, 0, Dict{String,Any}())

"""
    SGDOptimizer

Stochastic gradient descent with optional momentum and weight decay.
v_t = μ·v_{t-1} + g;  θ_t = θ_{t-1} - lr·v_t - wd·θ_{t-1}
"""
mutable struct SGDOptimizer
    lr       :: Float64
    momentum :: Float64
    wd       :: Float64
    state    :: Dict{String, Any}
end

SGDOptimizer(; lr=1e-2, momentum=0.9, wd=1e-4) =
    SGDOptimizer(lr, momentum, wd, Dict{String,Any}())

# ── Gradient computation (finite-difference autograd) ────────────────────────

"""
    numerical_gradient(f, θ; ε)

Compute ∂f/∂θ via central finite differences.  Used as a reference
implementation; production paths use analytic gradients.
"""
function numerical_gradient(f, θ::AbstractVector; ε::Float64=1e-5)
    grad = similar(θ)
    for i in eachindex(θ)
        θ_plus  = copy(θ); θ_plus[i]  += ε
        θ_minus = copy(θ); θ_minus[i] -= ε
        grad[i] = (f(θ_plus) - f(θ_minus)) / (2ε)
    end
    grad
end

# ── Loss functions ────────────────────────────────────────────────────────────

mse_loss(ŷ, y) = mean((ŷ .- y).^2)
mae_loss(ŷ, y) = mean(abs.(ŷ .- y))

function bce_loss(ŷ::AbstractArray, y::AbstractArray; ε::Float64=1e-7)
    ŷ_clip = clamp.(ŷ, ε, 1-ε)
    -mean(y .* log.(ŷ_clip) .+ (1 .- y) .* log.(1 .- ŷ_clip))
end

function cross_entropy_loss(logits::AbstractMatrix, y_int::AbstractVector)
    # logits: n_classes × batch
    n = length(y_int)
    p = softmax(logits)
    -mean(log(p[y_int[i], i] + 1e-7) for i in 1:n)
end

# ── MLP parameter flattening / unflattening ───────────────────────────────────

function _mlp_params(net::MLP)
    θ = Float64[]
    for l in net.layers
        append!(θ, vec(l.W))
        append!(θ, l.b)
    end
    θ
end

function _mlp_shapes(net::MLP)
    shapes = Tuple{Symbol,Tuple}[]
    for (i, l) in enumerate(net.layers)
        push!(shapes, (:W, size(l.W)))
        push!(shapes, (:b, size(l.b)))
    end
    shapes
end

# ── Analytic gradient for MLP via backprop ────────────────────────────────────

"""
    backprop_mlp(net, X, y, loss_fn)

Reverse-mode backpropagation through an MLP.
Returns (loss, grad_W_list, grad_b_list).
"""
function backprop_mlp(net::MLP, X::AbstractMatrix, y::AbstractVecOrMat, loss_fn)
    # Forward pass — cache activations and pre-activations
    n_layers = length(net.layers)
    zs = Vector{Matrix{Float64}}(undef, n_layers)
    as = Vector{Matrix{Float64}}(undef, n_layers + 1)
    as[1] = X  # as[i] = activation after layer i-1

    for i in 1:n_layers
        l = net.layers[i]
        z = l.W * as[i] .+ l.b
        zs[i] = z
        act = activation_fn(l.act)
        as[i+1] = act(z)
    end

    # Compute loss
    ŷ = as[end]
    loss = loss_fn(ŷ, y)

    # Backward pass
    grad_W = [zeros(size(l.W)) for l in net.layers]
    grad_b = [zeros(size(l.b)) for l in net.layers]
    batch  = size(X, 2)

    # Output layer gradient
    δ = (ŷ .- y) ./ batch

    for i in n_layers:-1:1
        l = net.layers[i]
        act_sym = l.act
        # Activation derivative
        if act_sym == :relu
            d_act = Float64.(zs[i] .> 0)
        elseif act_sym == :sigmoid
            s = sigmoid(zs[i])
            d_act = s .* (1 .- s)
        elseif act_sym == :tanh
            d_act = 1 .- tanh.(zs[i]).^2
        else
            d_act = ones(size(zs[i]))
        end

        δ = δ .* d_act
        grad_W[i] = δ * as[i]'
        grad_b[i] = vec(sum(δ; dims=2))
        δ = l.W' * δ
    end

    loss, grad_W, grad_b
end

# ── Adam update step ─────────────────────────────────────────────────────────

function adam_update!(opt::AdamOptimizer, key::String,
                       param::AbstractArray, grad::AbstractArray)
    if !haskey(opt.state, key * "_m")
        opt.state[key * "_m"] = zeros(size(param))
        opt.state[key * "_v"] = zeros(size(param))
    end
    m = opt.state[key * "_m"]
    v = opt.state[key * "_v"]
    m .= opt.β1 .* m .+ (1 - opt.β1) .* grad
    v .= opt.β2 .* v .+ (1 - opt.β2) .* grad.^2
    m̂ = m ./ (1 - opt.β1^opt.t)
    v̂ = v ./ (1 - opt.β2^opt.t)
    param .-= opt.lr .* m̂ ./ (sqrt.(v̂) .+ opt.ε)
end

# ── Mini-batch iterator ───────────────────────────────────────────────────────

"""
    minibatch_iter(X, y, batch_size; shuffle)

Yield (X_batch, y_batch) pairs of size batch_size.
"""
function minibatch_iter(X::AbstractMatrix, y::AbstractVecOrMat, batch_size::Int;
                        shuffle::Bool=true, rng=Random.GLOBAL_RNG)
    n = size(X, 2)
    idx = shuffle ? randperm(rng, n) : (1:n)
    batches = Tuple{Matrix{Float64}, Any}[]
    for start in 1:batch_size:n
        stop = min(start + batch_size - 1, n)
        bi = idx[start:stop]
        yb = y isa AbstractMatrix ? y[:, bi] : y[bi]
        push!(batches, (X[:, bi], yb))
    end
    batches
end

# ── Early stopping callback ───────────────────────────────────────────────────

"""
    EarlyStoppingCallback

Monitor validation loss; restore best weights after patience epochs.
"""
mutable struct EarlyStoppingCallback
    patience     :: Int
    min_delta    :: Float64
    best_loss    :: Float64
    wait         :: Int
    best_epoch   :: Int
    should_stop  :: Bool
end

EarlyStoppingCallback(; patience::Int=10, min_delta::Float64=1e-4) =
    EarlyStoppingCallback(patience, min_delta, Inf, 0, 0, false)

function update!(cb::EarlyStoppingCallback, val_loss::Float64, epoch::Int)
    if val_loss < cb.best_loss - cb.min_delta
        cb.best_loss  = val_loss
        cb.best_epoch = epoch
        cb.wait = 0
    else
        cb.wait += 1
        if cb.wait >= cb.patience
            cb.should_stop = true
        end
    end
end

# ── Cosine learning rate schedule ────────────────────────────────────────────

"""
    CosineSchedule(lr_max, lr_min, n_epochs)

η_t = η_min + ½(η_max - η_min)(1 + cos(πt/T))
"""
struct CosineSchedule
    lr_max   :: Float64
    lr_min   :: Float64
    n_epochs :: Int
end

function lr_at(sched::CosineSchedule, epoch::Int)
    t = clamp(epoch - 1, 0, sched.n_epochs - 1)
    sched.lr_min + 0.5 * (sched.lr_max - sched.lr_min) * (1 + cos(π * t / sched.n_epochs))
end

# ── Main training loop ────────────────────────────────────────────────────────

"""
    train!(net, X_train, y_train; kwargs...) -> TrainingHistory

Train an MLP via mini-batch Adam with optional validation, early stopping,
and learning rate scheduling.

Returns a `TrainingHistory` with per-epoch train/val losses.
"""
struct TrainingHistory
    train_loss  :: Vector{Float64}
    val_loss    :: Vector{Float64}
    epochs      :: Int
    best_epoch  :: Int
    final_lr    :: Float64
end

function train!(
    net        :: MLP,
    X_train    :: AbstractMatrix,
    y_train    :: AbstractVecOrMat;
    X_val      :: Union{AbstractMatrix, Nothing} = nothing,
    y_val      :: Union{AbstractVecOrMat, Nothing} = nothing,
    n_epochs   :: Int     = 100,
    batch_size :: Int     = 32,
    lr         :: Float64 = 1e-3,
    loss_fn                = mse_loss,
    schedule   :: Union{CosineSchedule, Nothing} = nothing,
    early_stop :: Union{EarlyStoppingCallback, Nothing} = nothing,
    verbose    :: Bool    = false,
    rng                    = Random.GLOBAL_RNG,
)
    opt = AdamOptimizer(; lr=lr)
    train_losses = Float64[]
    val_losses   = Float64[]

    for epoch in 1:n_epochs
        # Learning rate schedule
        if !isnothing(schedule)
            opt.lr = lr_at(schedule, epoch)
        end

        # Mini-batch gradient descent
        batches = minibatch_iter(X_train, y_train, batch_size; shuffle=true, rng=rng)
        epoch_loss = 0.0
        for (Xb, yb) in batches
            opt.t += 1
            loss, gW, gb = backprop_mlp(net, Xb, yb, loss_fn)
            epoch_loss += loss

            # In-place Adam updates (mutate W and b directly)
            for (i, l) in enumerate(net.layers)
                # Reconstruct mutable copies
                W_new = copy(l.W)
                b_new = copy(l.b)
                adam_update!(opt, "W$(i)", W_new, gW[i])
                adam_update!(opt, "b$(i)", b_new, gb[i])
                # Replace layer (structs are immutable; rebuild)
                net.layers[i] = Dense(W_new, b_new, l.act, l.in_f, l.out_f)
            end
        end
        push!(train_losses, epoch_loss / length(batches))

        # Validation
        if !isnothing(X_val) && !isnothing(y_val)
            ŷ_val = forward(net, X_val; training=false)
            vl = loss_fn(ŷ_val, y_val)
            push!(val_losses, vl)
            if !isnothing(early_stop)
                update!(early_stop, vl, epoch)
                early_stop.should_stop && break
            end
        end

        verbose && epoch % 10 == 0 &&
            @info "Epoch $epoch | train=$(round(last(train_losses);digits=4))"
    end

    best_e = isnothing(early_stop) ? n_epochs : early_stop.best_epoch
    TrainingHistory(train_losses, val_losses, length(train_losses), best_e, opt.lr)
end

# ── Evaluation ────────────────────────────────────────────────────────────────

"""
    evaluate_model(net, X, y; task) -> NamedTuple

Compute evaluation metrics.  task=:regression or :classification.
"""
function evaluate_model(net::MLP, X::AbstractMatrix, y::AbstractVecOrMat;
                        task::Symbol=:regression)
    ŷ = forward(net, X; training=false)
    if task == :regression
        residuals = vec(ŷ) .- vec(y)
        rmse = sqrt(mean(residuals.^2))
        mae  = mean(abs.(residuals))
        ss_res = sum(residuals.^2)
        ss_tot = sum((vec(y) .- mean(y)).^2)
        r2 = 1 - ss_res / max(ss_tot, 1e-12)
        return (rmse=rmse, mae=mae, r2=r2, n=length(y))
    else
        # Binary classification
        ŷ_p = sigmoid.(vec(ŷ))
        ŷ_c = Int.(ŷ_p .>= 0.5)
        y_c = Int.(vec(y) .>= 0.5)
        acc = mean(ŷ_c .== y_c)
        # AUC via Mann-Whitney U
        pos = ŷ_p[y_c .== 1]
        neg = ŷ_p[y_c .== 0]
        if isempty(pos) || isempty(neg)
            auc = 0.5
        else
            auc = mean(p > n for p in pos, n in neg)
        end
        brier = mean((ŷ_p .- vec(y)).^2)
        return (accuracy=acc, auc=auc, brier=brier, n=length(y))
    end
end
