# report.jl — Causal inference summary report

struct CausalReport
    study_name::String
    n::Int
    n_treated::Int
    n_control::Int
    ps_log_lik::Float64
    ps_converged::Bool
    ipw_ate::Float64
    ipw_se::Float64
    aipw_ate::Float64
    aipw_se::Float64
    overlap_ate::Float64
    overlap_se::Float64
    att_matched::Float64
    att_se::Float64
    n_matched::Int
    caliper::Float64
    mean_smd_before::Float64
    mean_smd_after::Float64
    timestamp::String
end

function causal_report(D::AbstractVector, y::AbstractVector, X::AbstractMatrix;
                       study_name::String="Causal Study",
                       feature_names=["x$i" for i in 1:size(X,2)],
                       n_boot::Int=100,
                       rng=Random.default_rng())
    n = length(y)

    # PS model
    ps_model = ps_fit(D, X; feature_names=feature_names)
    ps       = ps_predict(ps_model, X)
    ps_tr, D_tr, y_tr, _ = ps_trim(ps, D, y)
    X_tr     = X[findall(e -> 0.05 <= e <= 0.95, ps), :]

    # IPW estimators
    ipw_r  = ipw_ate(D_tr, y_tr, ps_tr; estimator=:hajek, n_boot=n_boot, rng=rng)
    aipw_r = aipw_ate(D_tr, y_tr, ps_tr, X_tr; n_boot=n_boot, rng=rng)
    ov_r   = overlap_ate(D_tr, y_tr, ps_tr; n_boot=n_boot, rng=rng)

    # Matching
    mr     = nn_match(D_tr, y_tr, ps_tr, X_tr; n_boot=n_boot, rng=rng)
    smd_b  = isempty(mr.smd_before) ? NaN : mean(mr.smd_before)
    smd_a  = isempty(mr.smd_after)  ? NaN : mean(mr.smd_after)

    CausalReport(
        study_name, n, sum(D .== 1), sum(D .== 0),
        ps_model.log_lik, ps_model.converged,
        ipw_r.ate, ipw_r.se,
        aipw_r.ate, aipw_r.se,
        ov_r.ate, ov_r.se,
        mr.att, mr.se, mr.n_matched, mr.caliper,
        smd_b, smd_a,
        string(Dates.now())
    )
end

function print_causal_report(r::CausalReport)
    println("=" ^ 60)
    println("  Causal Inference Report: $(r.study_name)")
    println("=" ^ 60)
    println("  N=$(r.n)  treated=$(r.n_treated)  control=$(r.n_control)")
    println("  PS log-lik: $(round(r.ps_log_lik,digits=2))  converged: $(r.ps_converged)")
    println()
    println("  ATE Estimates:")
    println("    IPW (Hajek):  $(round(r.ipw_ate,digits=4)) ± $(round(r.ipw_se,digits=4))")
    println("    AIPW:         $(round(r.aipw_ate,digits=4)) ± $(round(r.aipw_se,digits=4))")
    println("    Overlap wt:   $(round(r.overlap_ate,digits=4)) ± $(round(r.overlap_se,digits=4))")
    println()
    println("  ATT (matched): $(round(r.att_matched,digits=4)) ± $(round(r.att_se,digits=4))")
    println("    Matched pairs: $(r.n_matched)  caliper: $(round(r.caliper,digits=4))")
    println("    Mean SMD before: $(round(r.mean_smd_before,digits=3))")
    println("    Mean SMD after:  $(round(r.mean_smd_after,digits=3))")
end

# Simple Dates shim (no dependency)
module Dates
    now() = "$(Base.time_ns())"
end
