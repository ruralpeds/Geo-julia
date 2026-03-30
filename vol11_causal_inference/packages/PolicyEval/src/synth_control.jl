# synth_control.jl — Synthetic control method (Abadie et al. 2010)

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

Synthetic control via Frank-Wolfe optimisation on the probability simplex.
`Y_treated_pre` is T_pre-vector; `Y_donors_pre` is T_pre × n_donors matrix.
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

    # Normalise to mean 0 / sd 1 for each variable
    μ  = mean(Y_donors_pre, dims=1)[:]
    σv = std(Y_donors_pre, dims=1)[:]; σv[σv .< 1e-8] .= 1.0
    Xd = (Y_donors_pre .- μ') ./ σv'
    xt = (Y_treated_pre .- μ)  ./ σv

    # Frank-Wolfe on simplex: min ‖xt - Xd·w‖²  s.t. w≥0, Σw=1
    w = fill(1.0/n_d, n_d)
    for t in 1:500
        grad = -2 * Xd' * (xt .- Xd * w)
        # Step: away from argmax, towards argmin
        s = argmin(grad)
        e_s = zeros(n_d); e_s[s] = 1.0
        γ   = 2.0 / (t + 2.0)
        w   = (1 - γ) .* w .+ γ .* e_s
        w   = max.(w, 0.0); w ./= sum(w)
    end

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

Compute treatment gaps: Y_treated - Y_donors·w at each period.
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
