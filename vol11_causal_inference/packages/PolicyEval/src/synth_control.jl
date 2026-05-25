# synth_control.jl — Synthetic control method (Abadie et al. 2010) using Optim.jl

struct SynthResult
    weights::Vector{Float64}      # donor weights w (sums to 1)
    donor_names::Vector{String}
    treated_name::String
    rmspe_pre::Float64            # pre-treatment RMSPE
    rmspe_post::Float64           # post-treatment RMSPE
    ratio::Float64                # rmspe_post / rmspe_pre (inference)
    placebo_ratios::Vector{Float64}  # placebo test ratios (one per donor)
end

"""
    synth_control(Y_treated_pre, Y_donors_pre, Y_treated_post, Y_donors_post;
                  donor_names, treated_name, n_placebo_iter) -> SynthResult

Synthetic control via constrained optimisation using Optim.jl on the
probability simplex: min ||Y_treated - Y_donors * w||^2  s.t. w >= 0, sum(w) = 1.

`Y_treated_pre` is T_pre-vector; `Y_donors_pre` is T_pre x n_donors matrix.
"""
function synth_control(Y_treated_pre::AbstractVector,
                       Y_donors_pre::AbstractMatrix,
                       Y_treated_post::AbstractVector,
                       Y_donors_post::AbstractMatrix;
                       donor_names=["d$i" for i in 1:size(Y_donors_pre,2)],
                       treated_name::String="treated",
                       n_placebo_iter::Int=min(size(Y_donors_pre,2), 20))
    T_pre, n_d = size(Y_donors_pre)
    T_post     = length(Y_treated_post)

    # Use raw values for the matching objective
    Xd = Y_donors_pre
    xt = Y_treated_pre

    # Optimise on unconstrained space using softmax transformation
    # w = softmax(θ) ensures w >= 0 and sum(w) = 1
    function objective(θ)
        # Softmax: w_i = exp(θ_i) / sum(exp(θ))
        θ_shift = θ .- maximum(θ)  # numerical stability
        ew = exp.(θ_shift)
        w = ew ./ sum(ew)
        sum((xt .- Xd * w).^2)
    end

    θ0 = zeros(n_d)  # uniform initialisation (softmax(0) = 1/n_d)
    result = Optim.optimize(objective, θ0, LBFGS();
                            autodiff=:forward)
    θ_opt = Optim.minimizer(result)

    # Convert back to weights via softmax
    θ_shift = θ_opt .- maximum(θ_opt)
    ew = exp.(θ_shift)
    w = ew ./ sum(ew)

    Y_synth_pre  = Y_donors_pre  * w
    Y_synth_post = Y_donors_post * w

    rmspe_pre  = sqrt(mean((Y_treated_pre  .- Y_synth_pre).^2))
    rmspe_post = sqrt(mean((Y_treated_post .- Y_synth_post).^2))
    ratio      = rmspe_post / max(rmspe_pre, 1e-10)

    # Placebo tests: apply to each donor as if it were treated
    placebo_ratios = Float64[]
    for j in 1:min(n_placebo_iter, n_d)
        donors_j  = Y_donors_pre[:,  setdiff(1:n_d, j)]
        donors_jp = Y_donors_post[:, setdiff(1:n_d, j)]
        treat_j   = Y_donors_pre[:,  j]
        treat_jp  = Y_donors_post[:, j]
        pr = synth_control(treat_j, donors_j, treat_jp, donors_jp;
                           n_placebo_iter=0).ratio
        push!(placebo_ratios, pr)
    end

    SynthResult(w, donor_names, treated_name,
                rmspe_pre, rmspe_post, ratio, placebo_ratios)
end

"""
    synth_gaps(Y_treated, Y_donors, weights) -> Vector{Float64}

Compute treatment gaps: Y_treated - Y_donors*w at each period.
"""
function synth_gaps(Y_treated::AbstractVector,
                    Y_donors::AbstractMatrix,
                    weights::AbstractVector)
    Y_treated .- Y_donors * weights
end

"""
    synth_placebo(result) -> NamedTuple

Summarise placebo inference: rank of treated unit's RMSPE ratio
among all placebo ratios. p-value = rank/n_placebos.
"""
function synth_placebo(result::SynthResult)
    ratios = vcat(result.ratio, result.placebo_ratios)
    rank   = sum(ratios .>= result.ratio)
    p_val  = rank / length(ratios)
    (ratio=result.ratio, placebo_ratios=result.placebo_ratios,
     rank=rank, n_donors=length(result.placebo_ratios),
     p_value=p_val)
end
