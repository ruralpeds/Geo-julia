# ipw.jl — IPW, doubly-robust AIPW, and overlap weighting estimators

struct IPWResult
    estimator::Symbol         # :ht, :hajek, :aipw, :overlap
    ate::Float64
    se::Float64
    ci_lower::Float64
    ci_upper::Float64
    n::Int
    n_treated::Int
    n_control::Int
    weights_treated::Vector{Float64}
    weights_control::Vector{Float64}
end

# ── Outcome model: simple OLS ─────────────────────────────────────────────────

function _ols_predict(X_train, y_train, X_pred)
    Xb   = hcat(ones(size(X_train, 1)), X_train)
    Xp   = hcat(ones(size(X_pred,  1)), X_pred)
    β    = (Xb' * Xb + 1e-8*I) \ (Xb' * y_train)
    Xp * β
end

# ── Bootstrap SE helper ───────────────────────────────────────────────────────

function _bootstrap_se(fn, D, y, ps, X; n_boot=200, rng=Random.default_rng())
    n     = length(y)
    ests  = Vector{Float64}(undef, n_boot)
    for b in 1:n_boot
        idx     = rand(rng, 1:n, n)
        ests[b] = fn(D[idx], y[idx], ps[idx], isnothing(X) ? nothing : X[idx,:])
    end
    std(ests)
end

# ── Horwitz-Thompson (unnormalised) ATE ───────────────────────────────────────

function ipw_ate(D::AbstractVector, y::AbstractVector, ps::AbstractVector;
                 estimator::Symbol=:hajek, n_boot::Int=200,
                 rng=Random.default_rng())
    n = length(y)
    n_t = sum(D .== 1); n_c = sum(D .== 0)
    p̄   = mean(D)

    if estimator == :ht
        τ_fn = (d, yv, e, _) -> mean(d .* yv ./ e) - mean((1 .- d) .* yv ./ (1 .- e))
    else  # :hajek (normalised, more stable)
        τ_fn = (d, yv, e, _) -> begin
            μ1 = sum(d .* yv ./ e) / sum(d ./ e)
            μ0 = sum((1 .- d) .* yv ./ (1 .- e)) / sum((1 .- d) ./ (1 .- e))
            μ1 - μ0
        end
    end

    τ   = τ_fn(D, y, ps, nothing)
    se  = _bootstrap_se(τ_fn, D, y, ps, nothing; n_boot=n_boot, rng=rng)

    w_t = D ./ ps;  w_c = (1 .- D) ./ (1 .- ps)
    IPWResult(estimator, τ, se, τ-1.96se, τ+1.96se, n, n_t, n_c, w_t, w_c)
end

# ── Augmented IPW (doubly-robust AIPW) ───────────────────────────────────────

"""
    aipw_ate(D, y, ps, X; n_boot, rng) -> IPWResult

Doubly-robust AIPW estimator (Robins et al. 1994).
Consistent if either the propensity score model or the outcome model is correct.
"""
function aipw_ate(D::AbstractVector, y::AbstractVector,
                  ps::AbstractVector, X::AbstractMatrix;
                  n_boot::Int=200, rng=Random.default_rng())
    n   = length(y)
    D   = Float64.(D)
    τ_fn = (d, yv, e, Xm) -> begin
        idx1 = d .== 1; idx0 = d .== 0
        μ̂1   = _ols_predict(Xm[idx1,:], yv[idx1], Xm)
        μ̂0   = _ols_predict(Xm[idx0,:], yv[idx0], Xm)
        ψ    = (μ̂1 .- μ̂0) .+
               d .* (yv .- μ̂1) ./ e .-
               (1 .- d) .* (yv .- μ̂0) ./ (1 .- e)
        mean(ψ)
    end

    τ   = τ_fn(D, y, ps, X)
    se  = _bootstrap_se(τ_fn, D, y, ps, X; n_boot=n_boot, rng=rng)
    n_t = Int(sum(D .== 1)); n_c = n - n_t
    w_t = D ./ ps;  w_c = (1 .- D) ./ (1 .- ps)
    IPWResult(:aipw, τ, se, τ-1.96se, τ+1.96se, n, n_t, n_c, w_t, w_c)
end

# ── Overlap / Average Treatment Effect on the Overlap Pop. ───────────────────

"""
    overlap_ate(D, y, ps; n_boot, rng) -> IPWResult

Overlap-weighted ATE (Li et al. 2018): weights w = e(1-e).
Optimally efficient for the overlap population (trimming-free).
"""
function overlap_ate(D::AbstractVector, y::AbstractVector,
                     ps::AbstractVector;
                     n_boot::Int=200, rng=Random.default_rng())
    n   = length(y)
    D   = Float64.(D)
    τ_fn = (d, yv, e, _) -> begin
        w   = e .* (1 .- e)
        μ1  = sum(w .* d .* yv ./ e) / sum(w .* d ./ e)
        μ0  = sum(w .* (1 .- d) .* yv ./ (1 .- e)) / sum(w .* (1 .- d) ./ (1 .- e))
        μ1 - μ0
    end

    τ   = τ_fn(D, y, ps, nothing)
    se  = _bootstrap_se(τ_fn, D, y, ps, nothing; n_boot=n_boot, rng=rng)
    n_t = Int(sum(D .== 1)); n_c = n - n_t
    w_t = ps .* (1 .- ps) ./ ps     # = 1-ps on treated
    w_c = ps .* (1 .- ps) ./ (1 .- ps)  # = ps on controls
    IPWResult(:overlap, τ, se, τ-1.96se, τ+1.96se, n, n_t, n_c, w_t, w_c)
end
