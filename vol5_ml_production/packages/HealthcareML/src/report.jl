# report.jl — Automated ML report generation for healthcare access analysis
# Chapter 35.6

"""
    HealthcareMLReport

Container for a complete ML analysis report.
Produced by `generate_report`.
"""
struct HealthcareMLReport
    title          ::String
    model_name     ::String
    n_obs          ::Int
    n_features     ::Int
    cv_metric      ::Symbol
    cv_mean        ::Float64
    cv_std         ::Float64
    feature_importances::DataFrame
    top_shap_features  ::DataFrame
    calibration_data   ::Union{DataFrame,Nothing}
    created_at     ::String
end

"""
    generate_report(model, X, y, feature_names; title, cv_folds, shap_samples)
                   -> HealthcareMLReport

Run the complete ML reporting pipeline:
1. 5-fold cross-validation (RMSE + R²)
2. Permutation feature importance
3. Kernel SHAP values (top-10 features)
4. Calibration curve (if binary target provided)
"""
function generate_report(model       ::AccessModel,
                          X           ::AbstractMatrix,
                          y           ::AbstractVector,
                          feature_names::Vector{String} = String[];
                          title       ::String = "Healthcare Access ML Report",
                          cv_folds    ::Int    = 5,
                          shap_samples::Int    = 50,
                          binary_threshold::Union{Float64,Nothing} = nothing)

    n, p = size(X)
    fn   = isempty(feature_names) ? ["feature_$i" for i in 1:p] : feature_names

    # 1. CV
    cv = cross_validate(() -> deepcopy(model), X, y; folds=cv_folds, metric=:rmse)

    # 2. Fit on full data for importance/SHAP
    fit!(model, X, y)

    # 3. Permutation importance
    perm_imp = permutation_importance(model, X, y; feature_names=fn, n_repeats=5)

    # 4. SHAP (top-20 obs for speed)
    n_shap = min(shap_samples, n)
    shap_idx = randperm(n)[1:n_shap]
    shap_mat = shap_values(model, X[shap_idx, :]; n_samples=50)
    mean_abs_shap = vec(mean(abs.(shap_mat); dims=1))
    shap_df = sort(
        DataFrame(feature=fn, mean_abs_shap=mean_abs_shap),
        :mean_abs_shap; rev=true
    )

    # 5. Calibration (optional)
    calib = nothing
    if !isnothing(binary_threshold)
        probs  = predict_proba(model, X)
        y_bin  = Int.(y .>= binary_threshold)
        calib  = calibration_curve(probs, y_bin)
    end

    HealthcareMLReport(
        title, string(typeof(model)), n, p,
        :rmse, cv.mean_score, cv.std_score,
        perm_imp[1:min(10,nrow(perm_imp)), :],
        shap_df[1:min(10,nrow(shap_df)), :],
        calib,
        string(Dates.now())
    )
end

# Pretty-print
function Base.show(io::IO, r::HealthcareMLReport)
    println(io, "=" ^ 60)
    println(io, "  $(r.title)")
    println(io, "=" ^ 60)
    println(io, "  Model:      $(r.model_name)")
    println(io, "  Obs:        $(r.n_obs)  |  Features: $(r.n_features)")
    println(io, "  CV RMSE:    $(round(r.cv_mean; digits=5)) ± $(round(r.cv_std; digits=5))")
    println(io, "-" ^ 60)
    println(io, "  Top features by permutation importance:")
    for row in eachrow(r.feature_importances[1:min(5,nrow(r.feature_importances)), :])
        @printf(io, "    %-30s  Δ%.5f\n", row.feature, row.importance_mean)
    end
    println(io, "-" ^ 60)
    println(io, "  Top features by mean |SHAP|:")
    for row in eachrow(r.top_shap_features[1:min(5,nrow(r.top_shap_features)), :])
        @printf(io, "    %-30s  %.5f\n", row.feature, row.mean_abs_shap)
    end
    println(io, "=" ^ 60)
end

using Dates, Printf
