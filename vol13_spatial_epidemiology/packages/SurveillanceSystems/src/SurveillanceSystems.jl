"""
    SurveillanceSystems

Real-time disease surveillance for the Geo-Julia healthcare textbook.

Methods:
- **CUSUM** (Page 1954): one-sided / two-sided cumulative sum with reset option
- **EWMA** (Roberts 1959): exponentially weighted moving average
- **Farrington** (1996): quasi-Poisson regression baseline with overdispersion
- **CDC EARS** (Hutwagner 2003): C1 / C2 / C3 aberration statistics
- **Temporal scan** (Kulldorff 1997): most likely time window, Monte Carlo p-value
- **Prospective scan**: real-time end-of-series alerting
- Alert combination, sensitivity/specificity, threshold calibration
"""
module SurveillanceSystems

using Statistics, LinearAlgebra, Random
using Distributions: Poisson, Normal, quantile as dist_quantile

include("cusum.jl")
include("farrington.jl")
include("temporal_scan.jl")
include("report.jl")

export
    # CUSUM
    CUSUMResult, cusum, cusum_reset,
    # EWMA
    EWMAResult, ewma,
    # Farrington / EARS
    FarringtonResult, farrington,
    EARSResult, ears,
    calibrate_threshold,
    # Temporal scan
    TemporalScanResult, temporal_scan, prospective_scan,
    # Utilities
    combine_alerts, sensitivity_specificity,
    # Report
    print_surveillance_report

end # module
