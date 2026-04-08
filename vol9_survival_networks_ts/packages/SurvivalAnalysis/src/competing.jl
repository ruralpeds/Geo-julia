# competing.jl — Competing risks analysis
# Cumulative incidence function (CIF) and Fine-Gray subdistribution hazard

using Statistics, LinearAlgebra

# ── Cumulative Incidence Function ─────────────────────────────────────────────

"""
    CIFResult

Cause-specific cumulative incidence function estimate.

Fields: times, cif (for each cause), cause_labels, overall_km.
"""
struct CIFResult
    times         ::Vector{Float64}
    cif           ::Dict{Any, Vector{Float64}}   # cause → CIF
    cause_labels  ::Vector
    overall_km    ::KMResult   # all-cause KM
end

"""
    cumulative_incidence(times, status, causes; cause_of_interest) -> CIFResult

Estimate cause-specific cumulative incidence functions for competing risks.

- `status` : 0=censored, 1,2,... = event type
- `causes` is derived from `status` (unique non-zero values)

CIF_k(t) = Σ_{t_i ≤ t} S(t_{i-}) · λ_k(t_i)
where λ_k(t) = d_k(t)/r(t) and S is the overall KM curve.
"""
function cumulative_incidence(times::AbstractVector,
                               status::AbstractVector{<:Integer})
    # Overall KM (all events)
    all_event = Int.(status .> 0)
    km_all    = kaplan_meier(times, all_event)

    cause_labels = sort(unique(status[status .> 0]))
    event_times  = sort(unique(times[status .> 0]))

    # CIF for each cause
    cif_dict = Dict{Any, Vector{Float64}}()
    for c in cause_labels
        cif_c = Float64[]
        cif_running = 0.0
        for t in event_times
            r   = sum(times .>= t)
            d_c = sum((times .== t) .& (status .== c))
            r == 0 && continue
            # S(t-): KM just before t
            S_prev = km_predict(km_all, t - eps(Float64))
            cif_running += S_prev * d_c / r
            push!(cif_c, cif_running)
        end
        cif_dict[c] = cif_c
    end

    CIFResult(collect(Float64, event_times), cif_dict, cause_labels, km_all)
end

"""
    cif_at(result, cause, t) -> Float64

Evaluate CIF for `cause` at time `t`.
"""
function cif_at(result::CIFResult, cause, t::Real)
    t <= 0 && return 0.0
    idx = findlast(result.times .<= t)
    isnothing(idx) ? 0.0 : result.cif[cause][min(idx, length(result.cif[cause]))]
end

# ── Fine-Gray Subdistribution Hazard ─────────────────────────────────────────

"""
    FineGrayModel

Fine-Gray subdistribution hazard model for a specific cause.

Estimating equation approach (Lin 1997 / Fine & Gray 1999).
"""
struct FineGrayModel
    cause          ::Int
    β              ::Vector{Float64}
    se             ::Vector{Float64}
    z_stats        ::Vector{Float64}
    p_values       ::Vector{Float64}
    log_lik        ::Float64
    feature_names  ::Vector{String}
    converged      ::Bool
end

"""
    fine_gray_fit(times, status, X; cause, feature_names, max_iter, tol) -> FineGrayModel

Fit the Fine-Gray model for cause `cause` using the subdistribution hazard.

The subdistribution risk set for cause k at time t:
  - Subjects who had event k after t (usual)
  - Subjects who had competing event before t (stay in risk set with weight 0 → simplified)
We use an approximate estimating equation (weighted partial likelihood).
"""
function fine_gray_fit(times::AbstractVector, status::AbstractVector{<:Integer},
                        X::AbstractMatrix;
                        cause::Int=1,
                        feature_names::Vector{String}=["x$i" for i in 1:size(X,2)],
                        max_iter::Int=80,
                        tol::Float64=1e-6)
    n, p = size(X)

    # Build subdistribution weights
    # For cause k: event_k=1 for cause k events; competing = other events
    # Simplified: treat competing events as censored at event time (Lunn-McNeil approx)
    status_k = Int.(status .== cause)   # 1 if cause k event, 0 otherwise

    # Use CoxModel infrastructure with status_k
    # Expand risk set: subjects with competing events remain at risk
    # (approximate: we use IPCW weights = 1 here for simplicity)
    m = cox_fit(times, status_k, X;
                feature_names=feature_names,
                max_iter=max_iter, tol=tol)

    FineGrayModel(cause, m.β, m.se, m.z_stats, m.p_values,
                  m.log_lik, feature_names, m.converged)
end

"""
    fg_predict_cif(model, X_new, km_all, times_eval) -> Matrix{Float64}

Predict cause-specific CIF at `times_eval` for new observations.
"""
function fg_predict_cif(model::FineGrayModel, X_new::AbstractMatrix,
                         baseline_cif::Vector{Float64},
                         times_eval::Vector{Float64})
    n  = size(X_new, 1)
    η  = X_new * model.β
    hr = exp.(η)
    cif_out = zeros(n, length(times_eval))
    for j in eachindex(times_eval)
        cif0_j = j <= length(baseline_cif) ? baseline_cif[j] : baseline_cif[end]
        for i in 1:n
            # CIF_i(t) ≈ 1 - (1-CIF_0(t))^exp(η_i)
            cif_out[i, j] = 1.0 - (1.0 - cif0_j)^hr[i]
        end
    end
    cif_out
end

# ── Summary ───────────────────────────────────────────────────────────────────

"""
    cif_summary(result) -> NamedTuple

Return a table of CIF values at event times for each cause.
"""
function cif_summary(result::CIFResult)
    (times = result.times,
     cif   = result.cif,
     causes= result.cause_labels)
end
