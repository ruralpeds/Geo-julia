# population.jl — Population segmentation and predictive risk stratification

using Statistics, LinearAlgebra, Random

# ─── k-Means clustering ───────────────────────────────────────────────────────

struct KMeansResult
    labels::Vector{Int}          # cluster assignment for each unit
    centroids::Matrix{Float64}   # k × d centroids
    inertia::Float64             # total within-cluster sum of squares
    n_iter::Int
    converged::Bool
    k::Int; n::Int; d::Int
    cluster_sizes::Vector{Int}
    silhouette::Float64          # mean silhouette coefficient
end

"""
    kmeans(X, k; max_iter, tol, n_restarts, rng) -> KMeansResult

Lloyd's k-means with multiple random restarts; returns best (lowest inertia) run.

`X` is n × d. Initialisation: k-means++ (greedy distance-weighted seeding).
"""
function kmeans(X::AbstractMatrix, k::Int;
                max_iter::Int=300,
                tol::Float64=1e-6,
                n_restarts::Int=5,
                rng=Random.default_rng())
    n, d = size(X)
    k = min(k, n)
    k < 2 && error("k must be ≥ 2")

    best_labels = ones(Int, n); best_centroids = X[1:k, :]; best_inertia = Inf
    best_iter = 0; best_conv = false

    for _ in 1:n_restarts
        C  = _kmeanspp_init(X, k, rng)
        L  = zeros(Int, n)
        prev_inertia = Inf

        iter = 0; conv = false
        for it in 1:max_iter
            iter = it
            # Assign
            for i in 1:n
                dists = [sum((X[i,:] .- C[c,:]).^2) for c in 1:k]
                L[i]  = argmin(dists)
            end
            # Update centroids
            C_new = zeros(k, d)
            cnts  = zeros(Int, k)
            for i in 1:n; C_new[L[i],:] .+= X[i,:]; cnts[L[i]] += 1; end
            for c in 1:k
                cnts[c] > 0 ? (C_new[c,:] ./= cnts[c]) : (C_new[c,:] = X[rand(rng,1:n),:])
            end
            inertia = sum(sum((X[i,:] .- C_new[L[i],:]).^2) for i in 1:n)
            abs(prev_inertia - inertia) < tol && (conv = true; C = C_new; break)
            prev_inertia = inertia; C = C_new
        end
        inertia = sum(sum((X[i,:] .- C[L[i],:]).^2) for i in 1:n)
        if inertia < best_inertia
            best_inertia = inertia; best_labels = copy(L); best_centroids = copy(C)
            best_iter = iter; best_conv = conv
        end
    end

    sizes = [count(==(c), best_labels) for c in 1:k]
    sil   = _silhouette(X, best_labels, k)
    KMeansResult(best_labels, best_centroids, best_inertia, best_iter, best_conv,
                 k, n, d, sizes, sil)
end

function _kmeanspp_init(X::AbstractMatrix, k::Int, rng)
    n, d  = size(X)
    C     = zeros(k, d)
    C[1,:]= X[rand(rng, 1:n), :]
    for c in 2:k
        dists = [minimum(sum((X[i,:] .- C[j,:]).^2) for j in 1:c-1) for i in 1:n]
        probs = dists ./ max(sum(dists), 1e-12)
        cum   = cumsum(probs)
        r     = rand(rng)
        C[c,:]= X[searchsortedfirst(cum, r), :]
    end
    C
end

function _silhouette(X::AbstractMatrix, labels::Vector{Int}, k::Int)
    n = size(X, 1)
    n <= k && return 0.0
    s = 0.0
    for i in 1:n
        c = labels[i]
        same   = findall(==(c), labels)
        a = length(same) > 1 ? mean(sqrt(sum((X[i,:] .- X[j,:]).^2)) for j in same if j!=i) : 0.0
        b = minimum(mean(sqrt(sum((X[i,:] .- X[j,:]).^2)) for j in findall(==(c2), labels))
                    for c2 in 1:k if c2 != c && any(==(c2), labels))
        denom = max(a, b); denom < 1e-12 ? 0.0 : (s += (b - a)/denom)
    end
    s / n
end

# ─── Predictive risk scoring (logistic) ──────────────────────────────────────

struct PredictiveRiskResult
    β::Vector{Float64}       # logistic regression coefficients
    predicted_prob::Vector{Float64}  # P(outcome=1) for each unit
    calibration_slope::Float64       # slope of obs~pred regression (1.0 = perfect)
    calibration_intercept::Float64
    brier_score::Float64     # mean squared probability error
    c_statistic::Float64     # concordance = AUROC approximation
    n::Int; n_events::Int
end

"""
    predictive_risk(X, y; λ, max_iter, tol) -> PredictiveRiskResult

Fit a regularised logistic regression to predict binary health outcome `y`
from feature matrix `X` (n × d, with intercept prepended automatically).

- `λ` — L2 ridge penalty (default 0.01)
- Returns predicted probabilities, calibration metrics, and Brier score
"""
function predictive_risk(X::AbstractMatrix, y::AbstractVector;
                           λ::Float64=0.01,
                           max_iter::Int=100,
                           tol::Float64=1e-6)
    n, d = size(X)
    length(y) == n || error("X and y must have the same number of rows")
    # Add intercept
    Xb = hcat(ones(n), Float64.(X))
    yf = Float64.(y)

    β  = zeros(d+1)
    σ(z) = 1.0/(1.0+exp(-clamp(z,-20.0,20.0)))

    for _ in 1:max_iter
        p  = σ.(Xb * β)
        W  = p .* (1 .- p)
        g  = Xb' * (p .- yf) .+ λ .* [0.0; β[2:end]]
        H  = Xb' * (W .* Xb) .+ λ .* Diagonal([0.0; ones(d)])
        Δβ = H \ g
        β .-= Δβ
        norm(Δβ) < tol && break
    end

    probs = σ.(Xb * β)
    brier = mean((probs .- yf).^2)

    # Calibration (Hosmer-Lemeshow O/E regression on deciles)
    cal = _calibration_slope(probs, yf)

    # C-statistic (approximate AUROC via Mann-Whitney U)
    c_stat = _c_statistic(probs, yf)

    PredictiveRiskResult(β, probs, cal.slope, cal.intercept,
                          brier, c_stat, n, Int(sum(yf)))
end

function _calibration_slope(p̂::Vector{Float64}, y::Vector{Float64})
    logit(x) = log(clamp(x,1e-6,1-1e-6)/(1-clamp(x,1e-6,1-1e-6)))
    lp = logit.(p̂)
    lp̄, ȳ = mean(lp), mean(y)
    slope = sum((lp .- lp̄) .* (y .- ȳ)) / max(sum((lp .- lp̄).^2), 1e-12)
    intercept = ȳ - slope * lp̄
    (slope=slope, intercept=intercept)
end

function _c_statistic(p̂::Vector{Float64}, y::Vector{Float64})
    events    = findall(y .== 1)
    non_events= findall(y .== 0)
    isempty(events) || isempty(non_events) && return 0.5
    concordant = sum(p̂[e] > p̂[n] for e in events for n in non_events)
    tied       = sum(p̂[e] == p̂[n] for e in events for n in non_events)
    (concordant + 0.5*tied) / (length(events)*length(non_events))
end
