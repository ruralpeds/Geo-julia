"""
    DeepHealth

Neural network architectures for healthcare access prediction.
Chapter 45 — Open-Source Healthcare GIS Textbook in Julia.

Provides Flux-backed implementations of:
- Layer primitives: Dense, BatchNorm, Dropout, MultiHeadAttention
- Network architectures: MLP, GNN, TabNet-style feature selection
- Training utilities: Adam, SGD, mini-batch, early stopping, LR schedules
- Healthcare models: AccessPredictor, ReadmissionRisk, SepsisAlert
- Reporting: training curves, metrics, feature attribution
"""
module DeepHealth

using LinearAlgebra, Statistics, Random, DataFrames
using Flux
using Optimisers
using Zygote

include("layers.jl")
include("networks.jl")
include("training.jl")
include("health_models.jl")
include("report.jl")

export
    # Layers
    Dense, BatchNorm, Dropout, MultiHeadAttention,
    forward, forward_train,
    # Networks
    MLP, GNNLayer, TabNetBlock,
    build_mlp, build_gnn,
    # Training
    AdamOptimizer, SGDOptimizer,
    train!, evaluate_model,
    EarlyStoppingCallback, CosineSchedule,
    minibatch_iter,
    # Health models
    AccessPredictor, ReadmissionRisk, SepsisAlert,
    predict_access, predict_readmission, alert_sepsis,
    # Report
    DeepHealthReport, deep_health_report,
    training_summary

end # module
