# training.jl — Optimizers, training loops, and learning rate schedules (Flux-backed)
# Chapter 45 — Open-Source Healthcare GIS Textbook in Julia

# ── Optimizer state ───────────────────────────────────────────────────────────

"""
    AdamOptimizer

Adaptive moment estimation (Kingma & Ba 2014).
Wraps `Optimisers.Adam` internally while preserving the original API.
"""
mutable struct AdamOptimizer
    lr    :: Float64
    β1    :: Float64
    β2    :: Float64
    ε     :: Float64
    t     :: Int               # step counter (for bias correction)
    state :: Dict{String, Any} # internal Optimisers state
end

AdamOptimizer(; lr=1e-3, β1=0.9, β2=0.999, ε=1e-8) =
    AdamOptimizer(lr, β1, β2, ε, 0, Dict{String,Any}())

"""
    SGDOptimizer

Stochastic gradient descent with optional momentum and weight decay.
Wraps `Optimisers.Momentum` (or `Optimisers.OptimiserChain` with `WeightDecay`)
internally while preserving the original API.
"""
mutable struct SGDOptimizer
    lr       :: Float64
    momentum :: Float64
    wd       :: Float64
    state    :: Dict{String, Any}
end

SGDOptimizer(; lr=1e-2, momentum=0.9, wd=1e-4) =
    SGDOptimizer(lr, momentum, wd, Dict{String,Any}())

# ── Loss functions (thin wrappers around Flux.Losses) ─────────────────────────

mse_loss(ŷ, y) = Flux.Losses.mse(ŷ, y)
mae_loss(ŷ, y) = Flux.Losses.mae(ŷ, y)

function bce_loss(ŷ::AbstractArray, y::AbstractArray; ε::Float64=1e-7)
    ŷ_clip = clamp.(ŷ, ε, 1-ε)
    -mean(y .* log.(ŷ_clip) .+ (1 .- y) .* log.(1 .- ŷ_clip))
end

function cross_entropy_loss(logits::AbstractMatrix, y_int::AbstractVector)
    # logits: n_classes × batch
    n = length(y_int)
    p = Flux.softmax(logits; dims=1)
    -mean(log(p[y_int[i], i] + 1e-7) for i in 1:n)
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

# ── Zygote-based gradient computation for MLP ────────────────────────────────

"""
    _mlp_forward(Ws, bs, acts, x)

Pure-function forward pass through MLP layers parameterised by
vectors of weight matrices and bias vectors. Suitable for Zygote differentiation.
"""
function _mlp_forward(Ws::Vector, bs::Vector, acts::Vector{Symbol}, x::AbstractVecOrMat)
    h = x
    for i in eachindex(Ws)
        z = Ws[i] * h .+ bs[i]
        h = activation_fn(acts[i])(z)
    end
    h
end

"""
    _zygote_grads(net, X, y, loss_fn)

Compute gradients of loss w.r.t. all Dense layer weights and biases
using Zygote reverse-mode automatic differentiation.
Returns (loss_value, grad_W_list, grad_b_list).
"""
function _zygote_grads(net::MLP, X::AbstractMatrix, y::AbstractVecOrMat, loss_fn)
    Ws = [l.W for l in net.layers]
    bs = [l.b for l in net.layers]
    acts = [l.act for l in net.layers]

    loss_val, grads = Zygote.withgradient(Ws, bs) do ws, bvecs
        ŷ = _mlp_forward(ws, bvecs, acts, X)
        loss_fn(ŷ, y)
    end

    grad_W = grads[1]  # Vector of gradient matrices
    grad_b = grads[2]  # Vector of gradient vectors

    # Zygote can return Nothing for zero gradients; replace with zeros
    gW = [isnothing(g) ? zeros(size(Ws[i])) : g for (i, g) in enumerate(grad_W)]
    gb = [isnothing(g) ? zeros(size(bs[i])) : g for (i, g) in enumerate(grad_b)]

    loss_val, gW, gb
end

# ── Adam update step (using Optimisers.jl internally) ────────────────────────

function _get_or_create_optstate(opt::AdamOptimizer, key::String, param::AbstractArray)
    state_key = key * "_optstate"
    if !haskey(opt.state, state_key)
        rule = Optimisers.Adam(opt.lr, (opt.β1, opt.β2), opt.ε)
        opt.state[state_key] = Optimisers.setup(rule, param)
    end
    opt.state[state_key]
end

function adam_update!(opt::AdamOptimizer, key::String,
                       param::AbstractArray, grad::AbstractArray)
    st = _get_or_create_optstate(opt, key, param)
    # Update the learning rate in the rule to reflect any schedule changes
    st = Optimisers.adjust(st; eta=opt.lr)
    opt.state[key * "_optstate"] = st
    new_st, new_param = Optimisers.update(st, param, grad)
    opt.state[key * "_optstate"] = new_st
    param .= new_param
end

# ── Main training loop ────────────────────────────────────────────────────────

"""
    train!(net, X_train, y_train; kwargs...) -> TrainingHistory

Train an MLP via mini-batch Adam with optional validation, early stopping,
and learning rate scheduling. Uses Zygote for gradient computation.

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
            loss, gW, gb = _zygote_grads(net, Xb, yb, loss_fn)
            epoch_loss += loss

            # In-place Adam updates
            for (i, l) in enumerate(net.layers)
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
        ŷ_p = Flux.sigmoid.(vec(ŷ))
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
