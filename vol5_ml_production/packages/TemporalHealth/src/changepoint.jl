# changepoint.jl — PELT changepoint detection for health outcome series
# Chapter 37.4
#
# Killick, Fearnhead & Eckley (2012) "Optimal Detection of Changepoints with a
# Linear Computational Cost", JASA 107(500), 1590-1598.

"""
    PELTResult

Result of PELT changepoint detection.
"""
struct PELTResult
    changepoints::Vector{Int}   # indices of detected changepoints
    n_segments  ::Int
    segment_means::Vector{Float64}
    cost        ::Float64
    penalty     ::Float64
end

"""
    detect_changepoints(ts; penalty=nothing, cost=:normal_mean, min_seg=3)
                       -> PELTResult

PELT algorithm for optimal changepoint detection.

Cost functions:
- `:normal_mean` — change in mean, Gaussian noise: cost(y) = Σ(yᵢ - ȳ)²
- `:normal_var`  — change in variance: cost(y) = n·log(s²)
- `:poisson`     — change in rate (count data): cost = -2·n·log(λ̄)

`penalty`: log(n) by default (BIC-like); use 2·log(n) for HQC

Chapter 37.4 — "The PELT penalty encodes the trade-off between model fit
and complexity, analogous to the BIC penalty in regression."
"""
function detect_changepoints(ts       ::HealthTimeSeries;
                              penalty  ::Union{Float64,Nothing} = nothing,
                              cost_fn  ::Symbol = :normal_mean,
                              min_seg  ::Int    = 3)
    y = Float64.(ts.values)
    n = length(y)
    β = isnothing(penalty) ? log(n) : penalty

    # Precompute cumulative sums for O(1) segment cost evaluation
    S  = vcat(0.0, cumsum(y))
    S2 = vcat(0.0, cumsum(y.^2))

    _cost = if cost_fn == :normal_mean
        (s, e) -> begin
            len = e - s
            len < 1 && return 0.0
            μ = (S[e+1] - S[s+1]) / len
            S2[e+1] - S2[s+1] - len * μ^2
        end
    elseif cost_fn == :poisson
        (s, e) -> begin
            len = e - s
            len < 1 && return 0.0
            total = S[e+1] - S[s+1]
            total <= 0 && return 0.0
            -2.0 * total * log(total / len)
        end
    else  # normal_var
        (s, e) -> begin
            len = e - s
            len < 2 && return 0.0
            μ = (S[e+1] - S[s+1]) / len
            s2 = (S2[e+1] - S2[s+1]) / len - μ^2
            s2 <= 0 && return 0.0
            len * log(s2)
        end
    end

    # PELT DP
    F     = fill(Inf, n+1)
    F[1]  = -β
    τ_star = fill(0, n)
    cands  = [1]   # candidate changepoints (1-indexed positions in 0..n)

    for t in 1:n
        best_cost = Inf
        best_τ    = 0
        for τ in cands
            t - τ < min_seg && continue
            c = F[τ] + _cost(τ, t) + β
            if c < best_cost
                best_cost = c
                best_τ    = τ
            end
        end
        F[t+1]    = best_cost
        τ_star[t] = best_τ

        # PELT pruning: remove candidates where F[τ] + _cost(τ,t) > F[t+1]
        filter!(τ -> F[τ] + _cost(τ, t) <= F[t+1] + β, cands)
        push!(cands, t)
    end

    # Backtrace changepoints
    cps = Int[]
    t   = n
    while t > 0
        τ = τ_star[t]
        τ > 0 && τ < t && push!(cps, τ)
        t = τ
    end
    reverse!(cps)

    # Segment means
    segs = vcat(0, cps, n)
    seg_means = [(S[segs[i+1]+1] - S[segs[i]+1]) / max(segs[i+1]-segs[i], 1)
                  for i in 1:length(segs)-1]

    PELTResult(cps, length(segs)-1, seg_means, F[n+1], β)
end

function Base.show(io::IO, r::PELTResult)
    println(io, "PELTResult: $(r.n_segments) segments")
    println(io, "  Changepoints at: $(r.changepoints)")
    println(io, "  Segment means: $(round.(r.segment_means; digits=3))")
    println(io, "  Total cost: $(round(r.cost; digits=2))  Penalty: $(round(r.penalty; digits=2))")
end
