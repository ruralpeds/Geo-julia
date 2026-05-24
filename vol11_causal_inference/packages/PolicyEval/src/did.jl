# did.jl — Difference-in-differences and event study estimators using GLM.jl

struct DIDResult
    β_did::Float64        # ATT estimate
    se::Float64           # clustered bootstrap SE
    ci_lower::Float64
    ci_upper::Float64
    n::Int
    n_treated::Int
    n_control::Int
    pre_slope_diff::Float64   # parallel trends diagnostic
    pre_slope_pval::Float64
    estimator::Symbol    # :two_by_two or :twfe
end

# -- 2x2 DiD using GLM.jl -----------------------------------------------------

"""
    did_2x2(y, treat, post; unit_ids, n_boot, rng) -> DIDResult

Classic 2x2 difference-in-differences via regression:
    y = beta_0 + beta_1*treat + beta_2*post + beta_3*treat*post + eps
beta_3 is the DiD ATT estimate.
Clustered bootstrap SE by unit_ids.
"""
function did_2x2(y::AbstractVector, treat::AbstractVector, post::AbstractVector;
                 unit_ids=1:length(y),
                 n_boot::Int=200, rng=Random.default_rng())
    n   = length(y)
    D   = Float64.(treat); P = Float64.(post)

    # Fit DiD regression using GLM: y ~ treat * post
    df = DataFrame(y=Float64.(y), treat=D, post=P, treat_post=D .* P)
    model = lm(@formula(y ~ treat + post + treat_post), df)
    β_did = coef(model)[4]  # coefficient on treat_post interaction

    n_t  = sum(D .== 1) ÷ max(1, length(unique(P)))  # approx units
    n_c  = sum(D .== 0) ÷ max(1, length(unique(P)))

    # Cluster bootstrap by unit for proper SE
    β_fn = (yv, dv, pv) -> begin
        dfb = DataFrame(y=Float64.(yv), treat=Float64.(dv), post=Float64.(pv),
                        treat_post=Float64.(dv) .* Float64.(pv))
        mb = lm(@formula(y ~ treat + post + treat_post), dfb)
        coef(mb)[4]
    end

    units     = unique(unit_ids)
    boot_ests = Vector{Float64}(undef, n_boot)
    for b in 1:n_boot
        boot_u = rand(rng, units, length(units))
        idx    = vcat([findall(==(u), unit_ids) for u in boot_u]...)
        boot_ests[b] = β_fn(y[idx], D[idx], P[idx])
    end
    se = std(boot_ests)

    DIDResult(β_did, se, β_did-1.96se, β_did+1.96se, n, n_t, n_c, 0.0, NaN, :two_by_two)
end

"""
    event_study(y, treat, time; treat_time, unit_ids, n_boot, rng) -> NamedTuple

Event-study regression: y_{it} = Sum_tau beta_tau*Di*1(ti=tau) + alpha_i + gamma_t + eps_it
Returns beta_tau (tau normalised to 0 at treatment - 1 period).
"""
function event_study(y::AbstractVector, treat::AbstractVector,
                     time::AbstractVector;
                     treat_time::Real=0,
                     unit_ids=collect(1:length(y)),
                     n_boot::Int=200, rng=Random.default_rng())
    n = length(y)
    periods  = sort(unique(time))
    units_v  = sort(unique(unit_ids))
    rel_time = time .- treat_time

    # TWFE within-demean: remove unit and time FE
    rel_periods = sort(unique(rel_time))
    omit_t      = -1  # normalisation period

    D_event = zeros(n, length(rel_periods) - 1)
    keep    = filter(τ -> τ != omit_t, rel_periods)
    for (j, τ) in enumerate(keep)
        D_event[:, j] = Float64.(treat) .* Float64.(rel_time .== τ)
    end

    # Within transform (demean by unit and time)
    unit_grp = [findfirst(==(u), units_v) for u in unit_ids]
    time_grp = [findfirst(==(t), periods)  for t in time]

    Xy = hcat(D_event, y)
    # Demean by unit
    for g in 1:length(units_v)
        idx = unit_grp .== g
        Xy[idx,:] .-= mean(Xy[idx,:], dims=1)
    end
    # Demean by time
    for g in 1:length(periods)
        idx = time_grp .== g
        Xy[idx,:] .-= mean(Xy[idx,:], dims=1)
    end

    X_w = Xy[:, 1:end-1]; y_w = Xy[:, end]
    β   = (X_w'X_w + 1e-10*I) \ (X_w'y_w)

    # Bootstrap SE
    se_boot = zeros(length(β), n_boot)
    for b in 1:n_boot
        boot_u  = rand(rng, units_v, length(units_v))
        idx     = vcat([findall(==(u), unit_ids) for u in boot_u]...)
        isempty(idx) && continue
        XyB     = hcat(D_event[idx,:], y[idx])
        ug      = [findfirst(==(unit_ids[i]), units_v) for i in idx]
        tg      = [findfirst(==(time[i]), periods)  for i in idx]
        for g in 1:length(units_v)
            ii = ug .== g; any(ii) && (XyB[ii,:] .-= mean(XyB[ii,:], dims=1))
        end
        for g in 1:length(periods)
            ii = tg .== g; any(ii) && (XyB[ii,:] .-= mean(XyB[ii,:], dims=1))
        end
        Xb = XyB[:,1:end-1]; yb = XyB[:,end]
        se_boot[:,b] = (Xb'Xb + 1e-10*I) \ (Xb'yb)
    end
    ses = vec(std(se_boot, dims=2))

    (rel_periods=keep, β=β, se=ses, β_lower=β.-1.96.*ses, β_upper=β.+1.96.*ses)
end

"""
    parallel_trends_test(y, treat, time; treat_time, unit_ids, n_boot) -> NamedTuple

Test for pre-treatment parallel trends by running event study and checking
whether pre-period coefficients are jointly zero (Wald test).
"""
function parallel_trends_test(y, treat, time;
                               treat_time=0, unit_ids=collect(1:length(y)),
                               n_boot::Int=200, rng=Random.default_rng())
    es  = event_study(y, treat, time; treat_time=treat_time,
                      unit_ids=unit_ids, n_boot=n_boot, rng=rng)
    pre = es.rel_periods .< 0
    β_pre = es.β[pre]; se_pre = es.se[pre]
    # Joint Wald: chi2 = Sum (beta/se)^2
    chi2 = sum((β_pre ./ max.(se_pre, 1e-10)).^2)
    df   = sum(pre)
    # Chi-squared p-value using Distributions.jl
    p_val = 1.0 - cdf(Chisq(df), chi2)
    (chi2=chi2, df=df, p_value=p_val, pre_betas=β_pre, pre_ses=se_pre)
end

"""
    staggered_did(y, treat_cohort, time; n_boot, rng) -> NamedTuple

Simplified Callaway-Sant'Anna style ATT(g,t) aggregation.
treat_cohort = first treatment period for each unit (Inf for never-treated).
"""
function staggered_did(y::AbstractVector, treat_cohort::AbstractVector,
                       time::AbstractVector;
                       n_boot::Int=200, rng=Random.default_rng())
    cohorts = sort(unique(filter(isfinite, treat_cohort)))
    periods = sort(unique(time))
    n_units = length(unique(1:length(y)))  # simplified

    att_gt = Dict{Tuple,Float64}()
    for g in cohorts
        for t in periods[periods .>= g]
            # Treated group g at time t vs never-treated in clean controls
            treat_g = (treat_cohort .== g)
            ctrl    = .!isfinite.(treat_cohort)
            pre_t   = periods[periods .< g]
            isempty(pre_t) && continue
            t_pre   = last(pre_t)
            # 2x2 DiD: (treat_g, t) vs (treat_g, t_pre) minus (ctrl, t) vs (ctrl, t_pre)
            y11 = mean(y[(treat_g) .& (time .== t)])
            y10 = mean(y[(treat_g) .& (time .== t_pre)])
            y01 = mean(y[(ctrl)   .& (time .== t)])
            y00 = mean(y[(ctrl)   .& (time .== t_pre)])
            if any(isnan.([y11,y10,y01,y00])); continue; end
            att_gt[(g, t)] = (y11 - y10) - (y01 - y00)
        end
    end

    # Aggregate: simple average ATT
    vals = collect(values(att_gt))
    att_agg = isempty(vals) ? NaN : mean(vals)
    (att_gt=att_gt, att_agg=att_agg, n_cohorts=length(cohorts))
end
