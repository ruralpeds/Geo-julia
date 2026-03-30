# health_models.jl — Pre-built healthcare neural network models
# Chapter 45 — Open-Source Healthcare GIS Textbook in Julia

# ── Access Predictor ──────────────────────────────────────────────────────────

"""
    AccessPredictor

MLP regression model for healthcare access score prediction.
Inputs: demographic + geographic features (pop density, poverty rate, rurality,
        distance to nearest provider, insurance rate, etc.)
Output: continuous E2SFCA-style access score.
"""
struct AccessPredictor
    net          :: MLP
    feature_names :: Vector{String}
    μ            :: Vector{Float64}   # training mean for standardisation
    σ            :: Vector{Float64}   # training std
    history      :: Union{TrainingHistory, Nothing}
end

"""
    AccessPredictor(n_features; hidden=[64,32,16])

Construct an AccessPredictor with configurable architecture.
"""
function AccessPredictor(n_features::Int;
                         hidden::Vector{Int}=[64, 32, 16],
                         feature_names::Vector{String}=String[])
    net = build_mlp(n_features, hidden, 1;
                    activation=:relu,
                    use_bn=false,
                    dropout_p=0.1,
                    out_activation=:identity)
    if isempty(feature_names)
        feature_names = ["f$(i)" for i in 1:n_features]
    end
    AccessPredictor(net, feature_names, zeros(n_features), ones(n_features), nothing)
end

"""
    fit!(ap, X, y; kwargs...) -> AccessPredictor

Train the access predictor.  X: n_features × n_samples; y: n_samples.
Standardises inputs using training statistics.
"""
function fit!(ap::AccessPredictor, X::AbstractMatrix, y::AbstractVector;
              n_epochs=200, batch_size=32, lr=1e-3,
              val_frac=0.15, rng=Random.GLOBAL_RNG, verbose=false)
    n = size(X, 2)
    ap.μ .= vec(mean(X; dims=2))
    ap.σ .= max.(vec(std(X; dims=2)), 1e-8)
    X_std = (X .- ap.μ) ./ ap.σ

    # Train/val split
    n_val = max(1, round(Int, n * val_frac))
    idx = randperm(rng, n)
    val_idx = idx[1:n_val]; trn_idx = idx[n_val+1:end]

    X_tr = X_std[:, trn_idx]; y_tr = reshape(y[trn_idx], 1, :)
    X_vl = X_std[:, val_idx]; y_vl = reshape(y[val_idx], 1, :)

    es = EarlyStoppingCallback(; patience=20)
    hist = train!(ap.net, X_tr, y_tr;
                  X_val=X_vl, y_val=y_vl,
                  n_epochs=n_epochs, batch_size=batch_size, lr=lr,
                  early_stop=es, verbose=verbose, rng=rng)
    AccessPredictor(ap.net, ap.feature_names, ap.μ, ap.σ, hist)
end

"""
    predict_access(ap, X) -> Vector{Float64}

Predict access scores; applies the stored standardisation.
"""
function predict_access(ap::AccessPredictor, X::AbstractMatrix)
    X_std = (X .- ap.μ) ./ ap.σ
    vec(forward(ap.net, X_std; training=false))
end

# ── Readmission Risk Classifier ───────────────────────────────────────────────

"""
    ReadmissionRisk

Binary classifier for 30-day hospital readmission.
Features: age, diagnosis codes (one-hot or embedded), length-of-stay,
          comorbidity index, prior admissions, discharge disposition.
Output: P(readmission within 30 days).
"""
struct ReadmissionRisk
    net          :: MLP
    feature_names :: Vector{String}
    threshold    :: Float64    # decision threshold (default 0.5)
    μ            :: Vector{Float64}
    σ            :: Vector{Float64}
    history      :: Union{TrainingHistory, Nothing}
end

function ReadmissionRisk(n_features::Int;
                         hidden::Vector{Int}=[128, 64, 32],
                         threshold::Float64=0.5,
                         feature_names::Vector{String}=String[])
    net = build_mlp(n_features, hidden, 1;
                    activation=:relu,
                    use_bn=true,
                    dropout_p=0.2,
                    out_activation=:sigmoid)
    if isempty(feature_names)
        feature_names = ["f$(i)" for i in 1:n_features]
    end
    ReadmissionRisk(net, feature_names, threshold, zeros(n_features), ones(n_features), nothing)
end

function fit!(rr::ReadmissionRisk, X::AbstractMatrix, y::AbstractVector;
              n_epochs=200, batch_size=64, lr=5e-4,
              val_frac=0.2, rng=Random.GLOBAL_RNG, verbose=false)
    rr.μ .= vec(mean(X; dims=2))
    rr.σ .= max.(vec(std(X; dims=2)), 1e-8)
    X_std = (X .- rr.μ) ./ rr.σ

    n = size(X, 2)
    n_val = max(1, round(Int, n * val_frac))
    idx = randperm(rng, n)
    val_idx = idx[1:n_val]; trn_idx = idx[n_val+1:end]

    X_tr = X_std[:, trn_idx]; y_tr = reshape(Float64.(y[trn_idx]), 1, :)
    X_vl = X_std[:, val_idx]; y_vl = reshape(Float64.(y[val_idx]), 1, :)

    es = EarlyStoppingCallback(; patience=15)
    hist = train!(rr.net, X_tr, y_tr;
                  X_val=X_vl, y_val=y_vl,
                  n_epochs=n_epochs, batch_size=batch_size, lr=lr,
                  loss_fn=bce_loss, early_stop=es, verbose=verbose, rng=rng)
    ReadmissionRisk(rr.net, rr.feature_names, rr.threshold, rr.μ, rr.σ, hist)
end

"""
    predict_readmission(rr, X) -> (probabilities, labels)
"""
function predict_readmission(rr::ReadmissionRisk, X::AbstractMatrix)
    X_std = (X .- rr.μ) ./ rr.σ
    probs = vec(forward(rr.net, X_std; training=false))
    labels = Int.(probs .>= rr.threshold)
    probs, labels
end

# ── Sepsis Alert Model ────────────────────────────────────────────────────────

"""
    SepsisAlert

Early-warning classifier for sepsis onset using vital sign trajectories.
Combines temporal features (trend + variability) with static patient features.

Based on: Singer et al. (2016) Sepsis-3 definition criteria
- SOFA score components: respiratory, coagulation, liver, cardiovascular,
  CNS, renal
- Early deterioration patterns in vitals (HR, RR, MAP, Temperature, SpO2)
"""
struct SepsisAlert
    net          :: MLP
    feature_names :: Vector{String}
    alert_threshold :: Float64
    sensitivity_bias :: Float64    # >0 prefers sensitivity (fewer false negatives)
    μ            :: Vector{Float64}
    σ            :: Vector{Float64}
end

function SepsisAlert(n_features::Int;
                     hidden::Vector{Int}=[256, 128, 64],
                     alert_threshold::Float64=0.3,
                     sensitivity_bias::Float64=0.2,
                     feature_names::Vector{String}=String[])
    net = build_mlp(n_features, hidden, 1;
                    activation=:gelu,
                    use_bn=true,
                    dropout_p=0.3,
                    out_activation=:sigmoid)
    if isempty(feature_names)
        feature_names = ["f$(i)" for i in 1:n_features]
    end
    SepsisAlert(net, feature_names, alert_threshold, sensitivity_bias,
                zeros(n_features), ones(n_features))
end

"""
    alert_sepsis(sa, X) -> (risk_scores, alerts, severity)

Return risk scores in [0,1], binary alerts, and severity tier
(:low, :moderate, :high, :critical).
"""
function alert_sepsis(sa::SepsisAlert, X::AbstractMatrix)
    X_std = (X .- sa.μ) ./ sa.σ
    scores = vec(forward(sa.net, X_std; training=false))
    # Adjust threshold downward by sensitivity_bias to prefer recall
    adj_thresh = max(0.01, sa.alert_threshold - sa.sensitivity_bias)
    alerts = Int.(scores .>= adj_thresh)
    severity = map(scores) do s
        s < 0.2 ? :low : s < 0.4 ? :moderate : s < 0.7 ? :high : :critical
    end
    scores, alerts, severity
end

"""
    sofa_features(hr, rr, map_val, temp, spo2, creatinine, bilirubin, platelets)

Compute simplified SOFA-based feature vector from clinical measurements.
Returns a Vector{Float64} suitable as input to SepsisAlert.
"""
function sofa_features(;
    hr         :: Float64 = 80.0,
    rr         :: Float64 = 16.0,
    map_val    :: Float64 = 90.0,
    temp       :: Float64 = 37.0,
    spo2       :: Float64 = 98.0,
    creatinine :: Float64 = 1.0,
    bilirubin  :: Float64 = 0.8,
    platelets  :: Float64 = 200.0,
    # Trends (change per hour)
    Δhr  :: Float64 = 0.0,
    Δrr  :: Float64 = 0.0,
    Δmap :: Float64 = 0.0,
)
    # Normalise to approximate [0,1] clinical ranges
    Float64[
        hr / 120.0,
        rr / 30.0,
        (100.0 - map_val) / 60.0,    # higher = worse
        abs(temp - 37.0) / 3.0,
        (100.0 - spo2) / 20.0,
        min(creatinine / 4.0, 1.0),
        min(bilirubin / 6.0, 1.0),
        1.0 - min(platelets / 150.0, 1.0),
        Δhr / 20.0,
        Δrr / 8.0,
        Δmap / 20.0,
    ]
end
