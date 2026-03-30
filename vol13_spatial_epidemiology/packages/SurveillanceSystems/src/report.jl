# report.jl — Console reports for SurveillanceSystems

using Printf

function print_surveillance_report(cusum_r, ewma_r, ears_r, farr, scan_r;
                                    series_name::String="Case Series",
                                    time_unit::String="week")
    println("\n", "═"^64)
    println("  Surveillance Report — $(series_name)")
    println("═"^64)
    @printf "  Series length   : %d %ss\n" cusum_r.n time_unit
    @printf "  In-control mean : %.2f  SD: %.2f\n" cusum_r.μ₀ cusum_r.σ₀
    println()
    println("  Method          │ Alerts │ First alert")
    println("  ────────────────┼────────┼────────────")
    for (name, n_alert, times) in [
            ("CUSUM",    cusum_r.n_alerts, cusum_r.alert_times),
            ("EWMA",     ewma_r.n_alerts,  ewma_r.alert_times),
            ("EARS-C2",  sum(ears_r.alerts_C2), findall(ears_r.alerts_C2)),
            ("EARS-C3",  sum(ears_r.alerts_C3), findall(ears_r.alerts_C3)),
            ("Farrington", farr.n_alerts,  farr.alert_times),
        ]
        first_t = isempty(times) ? "—" : string(times[1])
        @printf "  %-16s│ %6d │ %s\n" name n_alert first_t
    end
    println()
    println("  Temporal Scan Statistic:")
    @printf "    LLR = %.3f  RR = %.2f  p = %.3f  %s\n" \
        scan_r.λ_obs scan_r.rr scan_r.p_value (scan_r.significant ? "SIGNIFICANT" : "n.s.")
    @printf "    Most likely cluster: %ss %d–%d  (obs=%d, exp=%.1f)\n" \
        time_unit scan_r.cluster_start scan_r.cluster_end \
        scan_r.cluster_cases scan_r.expected_cases
    println("═"^64)
end
