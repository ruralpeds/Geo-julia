# disparities.jl — Disparity decomposition methods for HealthEquity
# Chapter 48 — Open-Source Healthcare GIS Textbook in Julia

# ── Oaxaca-Blinder decomposition ──────────────────────────────────────────────

"""
    OaxacaResult

Oaxaca-Blinder decomposition of a mean outcome gap between two groups.
Total gap = Explained (endowments) + Unexplained (coefficients/discrimination).
"""
struct OaxacaResult
    total_gap   :: Float64   # ȳ_A - ȳ_B
    explained   :: Float64   # (X̄_A - X̄_B)'β_B  (endowment effect)
    unexplained :: Float64   # X̄_B'(β_A - β_B)  (coefficient effect)
    pct_explained :: Float64
    β_A         :: Vector{Float64}
    β_B         :: Vector{Float64}
    feature_contributions :: DataFrame   # per-feature breakdown
end

"""
    oaxaca_blinder(X_A, y_A, X_B, y_B) -> OaxacaResult

Decompose the outcome gap ȳ_A - ȳ_B into:
- Explained: differences in characteristics (X̄_A - X̄_B)'β_B
- Unexplained: differences in returns/discrimination X̄_B'(β_A - β_B)

Reference: Oaxaca (1973), Blinder (1973).
"""
function oaxaca_blinder(
    X_A :: AbstractMatrix,
    y_A :: AbstractVector,
    X_B :: AbstractMatrix,
    y_B :: AbstractVector;
    feature_names :: Vector{String} = String[],
)
    n_A, p = size(X_A); n_B = size(X_B, 1)
    if isempty(feature_names)
        feature_names = ["f$(i)" for i in 1:p]
    end

    # Add intercept
    X_A_aug = hcat(ones(n_A), X_A)
    X_B_aug = hcat(ones(n_B), X_B)

    # OLS coefficients for each group
    β_A = (X_A_aug' * X_A_aug + 1e-8I) \ (X_A_aug' * y_A)
    β_B = (X_B_aug' * X_B_aug + 1e-8I) \ (X_B_aug' * y_B)

    X̄_A = vec(mean(X_A; dims=1))
    X̄_B = vec(mean(X_B; dims=1))
    ȳ_A = mean(y_A); ȳ_B = mean(y_B)

    total_gap = ȳ_A - ȳ_B

    # Endowment effect (using B's coefficients as reference)
    X̄_A_aug = vcat(1.0, X̄_A)
    X̄_B_aug = vcat(1.0, X̄_B)
    explained   = dot(X̄_A_aug .- X̄_B_aug, β_B)
    unexplained = dot(X̄_B_aug, β_A .- β_B)

    pct_explained = abs(total_gap) > 1e-12 ? 100 * explained / total_gap : 0.0

    # Per-feature breakdown (skip intercept at index 1)
    feature_rows = []
    for (i, nm) in enumerate(feature_names)
        endow_i  = (X̄_A[i] - X̄_B[i]) * β_B[i+1]
        coef_i   = X̄_B[i] * (β_A[i+1] - β_B[i+1])
        push!(feature_rows, (feature=nm,
                              mean_A=X̄_A[i], mean_B=X̄_B[i],
                              β_A=β_A[i+1], β_B=β_B[i+1],
                              endowment=endow_i, coefficient=coef_i,
                              total=endow_i+coef_i))
    end
    feat_df = isempty(feature_rows) ? DataFrame() : DataFrame(feature_rows)

    OaxacaResult(total_gap, explained, unexplained, pct_explained,
                 β_A[2:end], β_B[2:end], feat_df)
end

function Base.show(io::IO, r::OaxacaResult)
    println(io, "Oaxaca-Blinder Decomposition")
    println(io, "  Total gap:    $(round(r.total_gap; digits=4))")
    println(io, "  Explained:    $(round(r.explained; digits=4)) ($(round(r.pct_explained;digits=1))%)")
    println(io, "  Unexplained:  $(round(r.unexplained; digits=4))")
end

# ── Theil between/within decomposition ───────────────────────────────────────

"""
    TheilDecomposition

Theil T index decomposed into between-group and within-group components.
T = T_B + T_W; T_B measures inequality attributable to group membership.
"""
struct TheilDecomposition
    total       :: Float64
    between     :: Float64   # T_B = Σ_g (n_g/n)(μ_g/μ) log(μ_g/μ)
    within      :: Float64   # T_W = Σ_g (n_g/n)(μ_g/μ) T_g
    groups      :: Vector{String}
    group_theil :: Vector{Float64}
    group_share :: Vector{Float64}   # contribution to total
end

"""
    theil_decompose(x, groups) -> TheilDecomposition

Decompose the Theil T index into between-group and within-group components.
"""
function theil_decompose(x::AbstractVector{<:Real}, groups::AbstractVector)
    n  = length(x)
    μ  = mean(x)
    abs(μ) < 1e-12 && return TheilDecomposition(0.0, 0.0, 0.0, String[], Float64[], Float64[])

    T_total = theil_index(x)
    ug = sort(string.(unique(groups)))

    n_g   = [sum(groups .== g) for g in ug]
    μ_g   = [mean(x[groups .== g]) for g in ug]
    T_g   = [theil_index(x[groups .== g]) for g in ug]

    # Between-group component
    T_B = sum((n_g[i]/n) * (μ_g[i]/μ) * log(μ_g[i]/max(μ, 1e-12))
              for i in eachindex(ug) if μ_g[i] > 0)

    # Within-group component
    T_W = sum((n_g[i]/n) * (μ_g[i]/μ) * T_g[i]
              for i in eachindex(ug))

    # Group contribution to total Theil
    group_share = [abs(T_total) > 1e-12 ?
                   ((n_g[i]/n) * (μ_g[i]/μ) * T_g[i]) / T_total : 0.0
                   for i in eachindex(ug)]

    TheilDecomposition(T_total, T_B, T_W, ug, T_g, group_share)
end

function Base.show(io::IO, d::TheilDecomposition)
    pct_B = abs(d.total) > 1e-12 ? round(100*d.between/d.total; digits=1) : 0.0
    println(io, "Theil Decomposition")
    println(io, "  Total:         $(round(d.total; digits=4))")
    println(io, "  Between-group: $(round(d.between; digits=4)) ($pct_B%)")
    println(io, "  Within-group:  $(round(d.within; digits=4))")
    println(io, "  Groups:        $(join(d.groups, ", "))")
end

# ── Concentration curve data ──────────────────────────────────────────────────

"""
    concentration_curve(y, rank_var; n_points) -> DataFrame

Compute the concentration curve: cumulative share of health outcome (y)
against cumulative share of population ranked by socioeconomic variable.
The area between the curve and the diagonal equals C/2 (concentration index).
"""
function concentration_curve(
    y        :: AbstractVector{<:Real},
    rank_var :: AbstractVector{<:Real};
    n_points :: Int = 50,
)
    n = length(y)
    order = sortperm(rank_var)
    y_sorted = y[order]

    cum_pop    = range(0, 1; length=n_points+1)
    cum_health = Float64[0.0]
    y_cum = cumsum(y_sorted)
    total = sum(y_sorted)

    for t in 1:n_points
        i = round(Int, t * n / n_points)
        push!(cum_health, total > 0 ? y_cum[min(i,n)] / total : t/n_points)
    end

    DataFrame(
        cum_population = collect(cum_pop),
        cum_health     = cum_health,
        lorenz_gap     = cum_health .- collect(cum_pop),  # positive = pro-rich
    )
end

# ── Relative/Slope index of inequality ────────────────────────────────────────

"""
    slope_index_inequality(y, rank_var) -> NamedTuple

Slope Index of Inequality (SII): regression of y on fractional rank.
Absolute SII = β₁ (difference from best-off to worst-off socioeconomic group).
Relative SII (RII) = β₁ / ȳ.
"""
function slope_index_inequality(y::AbstractVector{<:Real},
                                 rank_var::AbstractVector{<:Real})
    n = length(y)
    r = (sortperm(sortperm(rank_var)) .- 0.5) ./ n  # fractional rank
    X = hcat(ones(n), r)
    β = (X'X + 1e-8I) \ (X'y)
    μ = mean(y)
    (sii=β[2], rii=μ > 0 ? β[2]/μ : 0.0, intercept=β[1], mean=μ)
end
