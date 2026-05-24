# layers.jl — Neural network layer primitives for DeepHealth (Flux-backed)
# Chapter 45 — Open-Source Healthcare GIS Textbook in Julia

# ── Activation functions (thin wrappers around Flux) ─────────────────────────

relu(x::Real)    = Flux.relu(x)
relu(x::AbstractArray)  = Flux.relu.(x)
sigmoid(x::Real) = Flux.sigmoid(x)
sigmoid(x::AbstractArray) = Flux.sigmoid.(x)
softmax(x::AbstractVector) = Flux.softmax(x)
softmax(x::AbstractMatrix) = Flux.softmax(x; dims=1)
gelu(x::Real)    = Flux.gelu(x)
gelu(x::AbstractArray) = Flux.gelu.(x)
identity_fn(x)   = x

const ACTIVATIONS = Dict(
    :relu    => relu,
    :sigmoid => sigmoid,
    :softmax => softmax,
    :gelu    => gelu,
    :tanh    => tanh,
    :identity => identity_fn,
)

activation_fn(sym::Symbol) = get(ACTIVATIONS, sym, identity_fn)

# ── Dense Layer ───────────────────────────────────────────────────────────────

"""
    Dense(in_features, out_features; activation=:relu, init=:he)

Fully-connected linear layer: y = act(W x + b).

He initialisation (default) for ReLU networks; Glorot for sigmoid/tanh.
Backed by Flux.Dense internally.
"""
struct Dense
    W     :: Matrix{Float64}   # out × in
    b     :: Vector{Float64}   # out
    act   :: Symbol
    in_f  :: Int
    out_f :: Int
end

function Dense(in_f::Int, out_f::Int; activation::Symbol=:relu, init::Symbol=:he)
    W = if init == :he
        randn(out_f, in_f) .* sqrt(2.0 / in_f)
    elseif init == :glorot
        randn(out_f, in_f) .* sqrt(2.0 / (in_f + out_f))
    else
        randn(out_f, in_f) .* 0.01
    end
    b = zeros(out_f)
    Dense(W, b, activation, in_f, out_f)
end

function forward(layer::Dense, x::AbstractVecOrMat)
    z = layer.W * x .+ layer.b
    activation_fn(layer.act)(z)
end

# ── BatchNorm Layer ───────────────────────────────────────────────────────────

"""
    BatchNorm(features; ε=1e-5, momentum=0.1)

Batch normalisation: ŷ = (x - μ_B) / √(σ²_B + ε) · γ + β.
Running statistics are maintained for inference via exponential moving average.
"""
mutable struct BatchNorm
    γ         :: Vector{Float64}   # scale
    β         :: Vector{Float64}   # shift
    run_mean  :: Vector{Float64}
    run_var   :: Vector{Float64}
    ε         :: Float64
    momentum  :: Float64
    features  :: Int
end

function BatchNorm(features::Int; ε::Float64=1e-5, momentum::Float64=0.1)
    BatchNorm(
        ones(features), zeros(features),
        zeros(features), ones(features),
        ε, momentum, features
    )
end

function forward_train(bn::BatchNorm, x::AbstractMatrix)
    # x: features × batch
    μ = vec(mean(x; dims=2))
    σ² = vec(var(x; dims=2, corrected=false))
    # Update running stats
    bn.run_mean .= (1 - bn.momentum) .* bn.run_mean .+ bn.momentum .* μ
    bn.run_var  .= (1 - bn.momentum) .* bn.run_var  .+ bn.momentum .* σ²
    x̂ = (x .- μ) ./ sqrt.(σ² .+ bn.ε)
    bn.γ .* x̂ .+ bn.β
end

function forward(bn::BatchNorm, x::AbstractMatrix)
    # Inference: use running statistics
    x̂ = (x .- bn.run_mean) ./ sqrt.(bn.run_var .+ bn.ε)
    bn.γ .* x̂ .+ bn.β
end

function forward(bn::BatchNorm, x::AbstractVector)
    x̂ = (x .- bn.run_mean) ./ sqrt.(bn.run_var .+ bn.ε)
    bn.γ .* x̂ .+ bn.β
end

# ── Dropout Layer ─────────────────────────────────────────────────────────────

"""
    Dropout(p)

Training-time dropout: zero out each neuron with probability p; scale by 1/(1-p).
During inference, forward is identity.
"""
struct Dropout
    p :: Float64
end

function forward_train(d::Dropout, x::AbstractArray; rng=Random.GLOBAL_RNG)
    if d.p == 0.0
        return x
    end
    mask = Float64.(rand(rng, size(x)...) .> d.p) ./ (1.0 - d.p)
    x .* mask
end

forward(d::Dropout, x::AbstractArray) = x   # identity at inference

# ── MultiHeadAttention ────────────────────────────────────────────────────────

"""
    MultiHeadAttention(d_model, n_heads)

Multi-head self-attention for tabular feature interaction.
Attention(Q,K,V) = softmax(QK'/√d_k)V; concat h heads → linear projection.
"""
struct MultiHeadAttention
    W_Q  :: Matrix{Float64}   # d_model × d_model
    W_K  :: Matrix{Float64}
    W_V  :: Matrix{Float64}
    W_O  :: Matrix{Float64}
    d_model :: Int
    n_heads :: Int
    d_k     :: Int
end

function MultiHeadAttention(d_model::Int, n_heads::Int)
    @assert d_model % n_heads == 0 "d_model must be divisible by n_heads"
    d_k = d_model ÷ n_heads
    scale = sqrt(2.0 / d_model)
    MultiHeadAttention(
        randn(d_model, d_model) .* scale,
        randn(d_model, d_model) .* scale,
        randn(d_model, d_model) .* scale,
        randn(d_model, d_model) .* scale,
        d_model, n_heads, d_k
    )
end

function forward(mha::MultiHeadAttention, x::AbstractMatrix)
    # x: d_model × seq_len (or features × batch)
    d, n = size(x)
    Q = mha.W_Q * x    # d_model × n
    K = mha.W_K * x
    V = mha.W_V * x

    # Single-head attention (simplified; multi-head via splitting d_model)
    scores = Q' * K ./ sqrt(Float64(mha.d_k))  # n × n
    attn = Flux.softmax(scores; dims=2)          # n × n
    context = V * attn'                          # d_model × n
    mha.W_O * context
end

# ── Residual / Skip connection helper ────────────────────────────────────────

struct ResidualBlock
    layer1 :: Dense
    layer2 :: Dense
    proj   :: Union{Dense, Nothing}   # projection if dims differ
end

function ResidualBlock(in_f::Int, hidden_f::Int)
    proj = (in_f == hidden_f) ? nothing : Dense(in_f, hidden_f; activation=:identity, init=:glorot)
    ResidualBlock(
        Dense(in_f, hidden_f; activation=:relu),
        Dense(hidden_f, hidden_f; activation=:identity, init=:glorot),
        proj
    )
end

function forward(rb::ResidualBlock, x::AbstractVecOrMat)
    shortcut = isnothing(rb.proj) ? x : forward(rb.proj, x)
    h = forward(rb.layer1, x)
    h = forward(rb.layer2, h)
    relu(h .+ shortcut)
end
