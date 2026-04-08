# report.jl — Console reports for HealthIntelligence

using Printf, Statistics

function print_intelligence_report(risk_r, hni_r, lof_r, pr_r;
                                    label::String="Health Intelligence Report")
    println("\n", "═"^62)
    println("  $(label)")
    println("═"^62)

    println("\n  Risk Score Distribution:")
    for band in 1:4
        names = ["Low","Moderate","High","Very High"][band]
        n_b = sum(risk_r.quantile_band .== band)
        @printf "    Band %d (%9s): %3d units\n" band names n_b
    end

    println("\n  Health Needs Index (top 5 highest need):")
    top5 = sortperm(hni_r.index; rev=true)[1:min(5,hni_r.n)]
    for (rank, idx) in enumerate(top5)
        @printf "    %d. Unit %3d  HNI = %.1f  rank = %d\n" rank idx hni_r.index[idx] hni_r.rank[idx]
    end

    @printf "\n  LOF Anomaly Detection: %d outliers / %d units (k=%d)\n" \
        lof_r.n_outliers lof_r.n lof_r.k

    println("\n  Predictive Risk Model:")
    @printf "    C-statistic   : %.3f\n"  pr_r.c_statistic
    @printf "    Brier score   : %.4f\n"  pr_r.brier_score
    @printf "    Calibration   : slope=%.3f  intercept=%.3f\n" \
        pr_r.calibration_slope pr_r.calibration_intercept
    @printf "    Events / n    : %d / %d\n" pr_r.n_events pr_r.n
    println("═"^62)
end
