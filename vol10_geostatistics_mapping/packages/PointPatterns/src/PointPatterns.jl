"""
    PointPatterns

Pure-Julia spatial point pattern analysis for healthcare data.

Exports: kde2d, KDE2DResult, silverman_bandwidth, lcv_bandwidth,
hotspot_threshold, kde_intensity;
ripley_k, KFunctionResult, nnd_distribution, GFunctionResult,
pair_correlation;
dbscan, DBSCANResult, knox_test, KnoxResult,
spatial_scan_points, ScanPointResult;
point_pattern_report, PointPatternReport, print_point_pattern_report
"""
module PointPatterns

using Statistics, LinearAlgebra, Random

include("kde.jl")
include("ripley.jl")
include("clustering.jl")
include("report.jl")

export
    kde2d, KDE2DResult, silverman_bandwidth, lcv_bandwidth,
    hotspot_threshold, kde_intensity,
    ripley_k, KFunctionResult,
    nnd_distribution, GFunctionResult,
    pair_correlation,
    dbscan, DBSCANResult,
    knox_test, KnoxResult,
    spatial_scan_points, ScanPointResult,
    point_pattern_report, PointPatternReport, print_point_pattern_report

end
