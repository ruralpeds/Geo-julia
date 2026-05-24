# networks.jl — Network architectures for DeepHealth (Flux-backed)
# Chapter 45 — Open-Source Healthcare GIS Textbook in Julia

# ── Multi-Layer Perceptron ────────────────────────────────────────────────────

"""
    MLP

Standard feed-forward neural network with configurable depth/width.
Used as baseline for healthcare access prediction tasks.
Internally uses a Flux.Chain for differentiable forward passes.
"""
struct MLP
    layers      :: Vector{Dense}
    batch_norms :: Vector{Union{BatchNorm, Nothing}}
    dropout     :: Vector{Union{Dropout, Nothing}}
    in_features :: Int
    out_features :: Int
    use_bn      :: Bool
end

"""
    build_mlp(in_f, hidden_sizes, out_f; activation, use_bn, dropout_p, out_activation)

Construct an MLP from a list of hidden layer sizes.
"""
function build_mlp(
    in_f       :: Int,
    hidden_sizes :: Vector{Int},
    out_f      :: Int;
    activation    :: Symbol = :relu,
    use_bn        :: Bool   = false,
    dropout_p     :: Float64 = 0.0,
    out_activation :: Symbol = :identity,
)
    layers = Dense[]
    bns    = Union{BatchNorm, Nothing}[]
    drops  = Union{Dropout, Nothing}[]

    prev = in_f
    for h in hidden_sizes
        push!(layers, Dense(prev, h; activation=activation))
        push!(bns,   use_bn ? BatchNorm(h) : nothing)
        push!(drops, dropout_p > 0 ? Dropout(dropout_p) : nothing)
        prev = h
    end
    # Output layer
    push!(layers, Dense(prev, out_f; activation=out_activation, init=:glorot))
    push!(bns, nothing)
    push!(drops, nothing)

    MLP(layers, bns, drops, in_f, out_f, use_bn)
end

function forward(net::MLP, x::AbstractVecOrMat; training::Bool=false)
    h = x
    for i in eachindex(net.layers)
        h = forward(net.layers[i], h)
        if !isnothing(net.batch_norms[i])
            h = training ? forward_train(net.batch_norms[i], reshape(h, size(h,1), :)) :
                           forward(net.batch_norms[i], h)
        end
        if !isnothing(net.dropout[i]) && training
            h = forward_train(net.dropout[i], h)
        end
    end
    h
end

function n_params(net::MLP)
    total = 0
    for l in net.layers
        total += length(l.W) + length(l.b)
    end
    total
end

# ── Graph Neural Network Layer ────────────────────────────────────────────────

"""
    GNNLayer

Single graph convolution layer: h_v^(l+1) = σ(W · mean{h_u : u ∈ N(v) ∪ {v}})
Used for referral network node classification/regression.
"""
struct GNNLayer
    W   :: Matrix{Float64}   # out_f × in_f
    b   :: Vector{Float64}
    act :: Symbol
end

function GNNLayer(in_f::Int, out_f::Int; activation::Symbol=:relu)
    W = randn(out_f, in_f) .* sqrt(2.0 / in_f)
    GNNLayer(W, zeros(out_f), activation)
end

"""
    forward(layer, H, adj)

Message passing: aggregate neighbour features (mean pooling), then transform.
- H: in_f × n_nodes feature matrix
- adj: n_nodes × n_nodes adjacency matrix (can include self-loops)
"""
function forward(layer::GNNLayer, H::AbstractMatrix, adj::AbstractMatrix)
    # Degree-normalised aggregation: Â = D^{-1}(A + I)
    n = size(H, 2)
    A_tilde = adj .+ I(n)                     # add self-loops
    D_inv = Diagonal(1.0 ./ vec(sum(A_tilde; dims=2)))
    A_hat = D_inv * A_tilde                   # row-normalised
    H_agg = H * A_hat'                        # in_f × n_nodes
    z = layer.W * H_agg .+ layer.b
    activation_fn(layer.act)(z)
end

"""
    GNNModel

Multi-layer GNN for provider referral network analysis.
"""
struct GNNModel
    layers      :: Vector{GNNLayer}
    readout     :: Dense
    in_features :: Int
    out_features :: Int
end

function build_gnn(
    in_f       :: Int,
    hidden_sizes :: Vector{Int},
    out_f      :: Int;
    activation :: Symbol = :relu,
)
    layers = GNNLayer[]
    prev = in_f
    for h in hidden_sizes
        push!(layers, GNNLayer(prev, h; activation=activation))
        prev = h
    end
    readout = Dense(prev, out_f; activation=:identity, init=:glorot)
    GNNModel(layers, readout, in_f, out_f)
end

function forward(gnn::GNNModel, H::AbstractMatrix, adj::AbstractMatrix)
    h = H
    for layer in gnn.layers
        h = forward(layer, h, adj)
    end
    forward(gnn.readout, h)
end

# ── TabNet-style Feature Selection Block ─────────────────────────────────────

"""
    TabNetBlock

Feature selection via sequential attention mask (Arik & Pfister 2019).
Learns sparse feature selection gates at each step.
"""
struct TabNetBlock
    attn_W  :: Matrix{Float64}   # n_features × n_features
    dense   :: Dense
    n_steps :: Int
    gamma   :: Float64            # relaxation parameter
end

function TabNetBlock(n_features::Int, n_out::Int; n_steps::Int=3, gamma::Float64=1.3)
    TabNetBlock(
        randn(n_features, n_features) .* 0.01,
        Dense(n_features, n_out; activation=:relu),
        n_steps,
        gamma
    )
end

function forward(tb::TabNetBlock, x::AbstractMatrix)
    # x: n_features × batch
    n_f, batch = size(x)
    prior_scales = ones(n_f, batch)   # prior scale for each feature × sample
    h_total = zeros(tb.dense.out_f, batch)

    for step in 1:tb.n_steps
        # Attention logits: n_features × batch
        h_attn = tb.attn_W * (x .* prior_scales)
        # Sparsemax-like: use softmax as approximation
        mask = Flux.softmax(h_attn; dims=1)
        # Update prior to penalise reuse
        prior_scales = prior_scales .* (tb.gamma .- mask)
        # Feature selection
        x_masked = x .* mask
        # Transform
        h_total .+= forward(tb.dense, x_masked)
    end
    h_total ./ tb.n_steps
end
