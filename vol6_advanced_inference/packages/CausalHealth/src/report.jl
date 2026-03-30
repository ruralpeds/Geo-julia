# report.jl — Causal inference summary report
# Chapter 43.5

using Printf

"""
    CausalReport

Aggregated causal inference findings across multiple methods.
"""
struct CausalReport
    method      ::String
    effect      ::Float64
    se          ::Float64
    p_value     ::Float64
    ci_lo       ::Float64
    ci_hi       ::Float64
    n_obs       ::Int
    notes       ::String
end

"""
    causal_summary(results::Vector{CausalReport}) -> DataFrame

Print a comparison table of causal estimates from multiple methods.
"""
function causal_summary(results::Vector{CausalReport})
    rows = [(method=r.method, effect=round(r.effect;digits=4),
             se=round(r.se;digits=4), p=round(r.p_value;digits=4),
             ci=@sprintf("[%.3f, %.3f]", r.ci_lo, r.ci_hi),
             n=r.n_obs, notes=r.notes)
            for r in results]
    DataFrame(rows)
end

function Base.show(io::IO, r::CausalReport)
    sig = r.p_value < 0.001 ? "***" : r.p_value < 0.01 ? "**" :
          r.p_value < 0.05  ? "*"   : ""
    @printf(io, "%-20s  τ = %+.4f  SE = %.4f  p = %.4f %s  [%.3f, %.3f]\n",
            r.method, r.effect, r.se, r.p_value, sig, r.ci_lo, r.ci_hi)
end

import DataFrames: DataFrame
