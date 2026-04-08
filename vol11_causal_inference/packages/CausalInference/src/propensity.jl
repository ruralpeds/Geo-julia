# propensity.jl — Logistic regression propensity score estimation

sigmoid(x::Real) = x > 0 ? 1.0/(1.0+exp(-x)) : exp(x)/(1.0+exp(x))

struct PropensityModel
    β::Vector{Float64}          # coefficients (intercept first)
    se::Vector{Float64}         # standard errors
    log_lik::Float64
    n_iter::Int
    converged::Bool
    feature_names::Vector{String}
end

"""
    ps_fit(D, X; feature_names, λ, max_iter, tol) -> PropensityModel

Estimate propensity scores via logistic regression using Newton-Raphson.
`D` is binary treatment (0/1), `X` is n×p covariate matrix (no intercept column).
Ridge penalty λ improves numerical stability.
"""
function ps_fit(D::AbstractVector, X::AbstractMatrix;
                feature_names=["x$i" for i in 1:size(X,2)],
                λ::Float64=1e-4, max_iter::Int=200, tol::Float64=1e-8)
    n, p = size(X)
    # Design matrix with intercept
    Xd = hcat(ones(n), X)
    β  = zeros(p + 1)
    converged = false
    n_iter = 0

    for iter in 1:max_iter
        η  = Xd * β
        p̂  = sigmoid.(η)
        # Gradient: ∇ℓ = X'(D - p̂) - λβ (no penalty on intercept)
        pen     = vcat(0.0, λ .* β[2:end])
        grad    = Xd' * (D .- p̂) .- pen
        # Hessian: H = -X'WX - λI (intercept excluded from penalty)
        W       = p̂ .* (1.0 .- p̂)
        H       = -(Xd' * (W .* Xd)) .- diagm(vcat(0.0, fill(λ, p)))
        # Newton step
        Δ = -H \ grad
        β += Δ
        n_iter = iter
        if norm(Δ) < tol; converged = true; break; end
    end

    η  = Xd * β
    p̂  = sigmoid.(η)
    ll = sum(D .* η .- log1p.(exp.(η)))
    # SE from inverse Hessian diagonal
    W    = p̂ .* (1.0 .- p̂)
    H    = -(Xd' * (W .* Xd)) .- diagm(vcat(0.0, fill(λ, p)))
    Hinv = inv(H)
    se   = sqrt.(abs.(diag(Hinv)))

    PropensityModel(β, se, ll, n_iter, converged, feature_names)
end

"""
    ps_predict(model, X) -> Vector{Float64}

Return estimated propensity scores e(X) = P(D=1|X).
"""
function ps_predict(model::PropensityModel, X::AbstractMatrix)
    n = size(X, 1)
    Xd = hcat(ones(n), X)
    sigmoid.(Xd * model.β)
end

"""
    ps_trim(ps, D, y; lo, hi) -> (ps_t, D_t, y_t, idx)

Trim to common support: keep obs with lo ≤ ps ≤ hi.
Default lo=0.05, hi=0.95 (Crump et al. 2009 rule-of-thumb is 0.1).
"""
function ps_trim(ps::AbstractVector, D::AbstractVector, y::AbstractVector;
                 lo::Float64=0.05, hi::Float64=0.95)
    idx = findall(e -> lo <= e <= hi, ps)
    ps[idx], D[idx], y[idx], idx
end

"""
    ps_overlap(ps, D) -> NamedTuple

Overlap diagnostics: min/max PS by arm, effective sample sizes.
"""
function ps_overlap(ps::AbstractVector, D::AbstractVector)
    ps0 = ps[D .== 0]; ps1 = ps[D .== 1]
    eff0 = sum(ps0 .* (1 .- ps0))^2 / sum((ps0 .* (1 .- ps0)).^2)
    eff1 = sum(ps1 .* (1 .- ps1))^2 / sum((ps1 .* (1 .- ps1)).^2)
    (n_treated=sum(D .== 1), n_control=sum(D .== 0),
     ps_min_treated=minimum(ps1), ps_max_treated=maximum(ps1),
     ps_min_control=minimum(ps0), ps_max_control=maximum(ps0),
     overlap_min=max(minimum(ps1), minimum(ps0)),
     overlap_max=min(maximum(ps1), maximum(ps0)),
     eff_n_treated=eff1, eff_n_control=eff0)
end
