# report.jl — Policy evaluation summary report

struct PolicyReport
    study_name::String
    method::Symbol        # :did, :synth, :rdd, or :combined
    did_att::Float64
    did_se::Float64
    synth_rmspe_ratio::Float64
    synth_placebo_p::Float64
    rdd_tau::Float64
    rdd_se::Float64
    rdd_bandwidth::Float64
    timestamp::String
end

function policy_report(;
        study_name::String="Policy Study",
        did_result=nothing, synth_result=nothing, rdd_result=nothing)
    did_att = isnothing(did_result) ? NaN : did_result.β_did
    did_se  = isnothing(did_result) ? NaN : did_result.se
    s_ratio = isnothing(synth_result) ? NaN : synth_result.ratio
    s_p     = isnothing(synth_result) ? NaN : synth_placebo(synth_result).p_value
    r_tau   = isnothing(rdd_result) ? NaN : rdd_result.τ
    r_se    = isnothing(rdd_result) ? NaN : rdd_result.se
    r_bw    = isnothing(rdd_result) ? NaN : rdd_result.bandwidth

    method = if !isnothing(did_result) && !isnothing(synth_result) && !isnothing(rdd_result)
        :combined
    elseif !isnothing(did_result)
        :did
    elseif !isnothing(synth_result)
        :synth
    else
        :rdd
    end

    PolicyReport(study_name, method, did_att, did_se, s_ratio, s_p,
                 r_tau, r_se, r_bw, "$(time_ns())")
end

function print_policy_report(r::PolicyReport)
    println("=" ^ 60)
    println("  Policy Evaluation Report: $(r.study_name)")
    println("=" ^ 60)
    if isfinite(r.did_att)
        println("  DiD ATT: $(round(r.did_att,digits=4)) ± $(round(r.did_se,digits=4))")
    end
    if isfinite(r.synth_rmspe_ratio)
        println("  Synth RMSPE ratio: $(round(r.synth_rmspe_ratio,digits=3))")
        println("  Synth placebo p:   $(round(r.synth_placebo_p,digits=4))")
    end
    if isfinite(r.rdd_tau)
        println("  RDD τ: $(round(r.rdd_tau,digits=4)) ± $(round(r.rdd_se,digits=4))")
        println("  RDD bandwidth: $(round(r.rdd_bandwidth,digits=4))")
    end
end
