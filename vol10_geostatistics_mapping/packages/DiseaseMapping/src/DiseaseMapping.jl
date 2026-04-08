"""
    DiseaseMapping

Pure-Julia Bayesian disease mapping for spatial epidemiology.

Exports: smr, batch_smr, smr_summary, SMRResult, indirect_standardise;
build_adjacency, bym_fit, BYMResult, rand_gamma;
eb_smooth, EBSmoothedResult, kernel_smooth_rates,
spatial_scan, ScanResult, rand_poisson;
disease_mapping_report, DiseaseMappingReport, print_disease_mapping_report
"""
module DiseaseMapping

using Statistics, LinearAlgebra, Random

include("smr.jl")
include("bym.jl")
include("smoothing.jl")
include("report.jl")

export
    smr, batch_smr, smr_summary, SMRResult, indirect_standardise,
    build_adjacency, bym_fit, BYMResult, rand_gamma,
    eb_smooth, EBSmoothedResult, kernel_smooth_rates,
    spatial_scan, ScanResult, rand_poisson,
    disease_mapping_report, DiseaseMappingReport, print_disease_mapping_report

end
