module GapAnalysisData

using DataFrames, Dates

export gap_items, volume_summaries, sciml_packages, migration_phases,
       GapItem, VolumeSummary, SciMLPackage, MigrationPhase,
       severity_counts, total_custom_loc, coverage_by_domain

struct GapItem
    id::Int
    domain::String
    custom_package::String
    custom_loc::Int
    replacement::String
    severity::String
    volume::String
    description::String
    status::String
end

struct VolumeSummary
    name::String
    custom_loc::Int
    num_packages::Int
    uses_ecosystem::Bool
    key_gaps::Vector{String}
end

struct SciMLPackage
    name::String
    category::String
    ecosystem::String
    maturity::String
    replaces::String
    url::String
end

struct MigrationPhase
    phase::Int
    title::String
    weeks::String
    items::Vector{String}
    priority::String
end

function gap_items()
    return [
        GapItem(1, "Deep Learning", "DeepHealth (layers.jl)", 199,
            "Flux.jl / Lux.jl", "CRITICAL", "Vol 7",
            "Custom Dense, BatchNorm, Dropout, MultiHeadAttention, ResidualBlock layers with He/Glorot init", "COMPLETED"),
        GapItem(2, "Deep Learning", "DeepHealth (training.jl)", 363,
            "Flux.jl + Optimisers.jl", "CRITICAL", "Vol 7",
            "Custom Adam, SGD+momentum, backpropagation, loss functions, mini-batch iterator, early stopping, cosine annealing", "COMPLETED"),
        GapItem(3, "Automatic Differentiation", "DeepHealth (training.jl)", 80,
            "Zygote.jl / Enzyme.jl", "CRITICAL", "Vol 7",
            "Finite-difference numerical gradients for all parameter updates — O(n) per param, prone to numerical error", "COMPLETED"),
        GapItem(4, "MCMC Sampling", "BayesianHealth (mcmc.jl)", 334,
            "Turing.jl + AdvancedMCMC.jl", "CRITICAL", "Vol 7",
            "Custom Metropolis-Hastings with dual-averaging, HMC with leapfrog integrator, Chains struct, R-hat, ESS", "COMPLETED"),
        GapItem(5, "Variational Inference", "BayesianHealth (vi.jl)", 209,
            "Turing.jl + AdvancedVI.jl", "CRITICAL", "Vol 7",
            "Custom mean-field Gaussian VI, ELBO via reparameterization, Adam ascent, posterior predictive", "COMPLETED"),
        GapItem(6, "ODE Integration", "NetworkHealth (epidemic.jl)", 309,
            "DifferentialEquations.jl", "CRITICAL", "Vol 9",
            "Custom RK4 integrator for SIR/SEIR/SEIRD compartmental models, stochastic tau-leaping network SIR", "COMPLETED"),
        GapItem(7, "ODE Integration", "InfectiousDisease (compartmental.jl)", 182,
            "DifferentialEquations.jl", "CRITICAL", "Vol 13",
            "Custom Euler + RK4 for SIR/SEIR, stochastic SIR with custom Poisson tau-leaping", "COMPLETED"),
        GapItem(8, "Gaussian Processes", "GaussianProcessHealth", 400,
            "AbstractGPs.jl + KernelFunctions.jl", "HIGH", "Vol 6",
            "Custom exact GP regression, kernel matrix computation, sparse GP, hyperparameter optimization", "COMPLETED"),
        GapItem(9, "Cox PH Model", "SurvivalAnalysis (cox.jl)", 226,
            "Survival.jl", "HIGH", "Vol 9",
            "Custom Breslow partial likelihood, Newton-Raphson, baseline hazard, Harrell's C-statistic", "COMPLETED"),
        GapItem(10, "Kaplan-Meier", "SurvivalAnalysis (estimators.jl)", 279,
            "Survival.jl", "HIGH", "Vol 9",
            "Custom KM product-limit, Greenwood variance, Nelson-Aalen, log-rank test, RMST", "COMPLETED"),
        GapItem(11, "Parametric Survival", "SurvivalAnalysis (parametric.jl)", 200,
            "Survival.jl", "HIGH", "Vol 9",
            "Custom Weibull/Exponential/Log-logistic AFT MLE with finite-difference Hessian", "COMPLETED"),
        GapItem(12, "Graph Algorithms", "NetworkHealth (graph.jl)", 288,
            "Graphs.jl", "HIGH", "Vol 9",
            "Custom adjacency list, Dijkstra, BFS, PageRank, betweenness centrality, clustering coefficient", "COMPLETED"),
        GapItem(13, "ARIMA", "TimeSeriesHealth (arima.jl)", 251,
            "StateSpaceModels.jl", "HIGH", "Vol 9",
            "Custom ACF/PACF, Yule-Walker AR, ARMA likelihood via innovations, auto-ARIMA grid search", "COMPLETED"),
        GapItem(14, "Kalman Filter", "TimeSeriesHealth (state_space.jl)", 233,
            "StateSpaceModels.jl / Kalman.jl", "HIGH", "Vol 9",
            "Custom Kalman filter/RTS smoother, EM for local-level DLM, local trend model, h-step forecast", "COMPLETED"),
        GapItem(15, "Variogram Fitting", "GeostatHealth (variogram.jl)", 248,
            "GeoStats.jl", "HIGH", "Vol 10",
            "Custom empirical variogram (Matheron + Cressie-Hawkins), spherical/exponential/Gaussian/Matern models, Nelder-Mead WLS fit", "COMPLETED"),
        GapItem(16, "Kriging", "GeostatHealth (kriging.jl)", 261,
            "GeoStats.jl", "HIGH", "Vol 10",
            "Custom Simple/Ordinary/Universal kriging with LOO cross-validation", "COMPLETED"),
        GapItem(17, "GWR", "SpatialRegression (gwr.jl)", 311,
            "GeoStats.jl + SpatialDependence.jl", "HIGH", "Vol 8",
            "Custom GWR with Gaussian/bisquare/Epanechnikov kernels, Haversine distances, AICc bandwidth selection", "COMPLETED"),
        GapItem(18, "Spatial Lag/Error", "SpatialRegression (spatial_lag.jl)", 158,
            "SpatialDependence.jl", "HIGH", "Vol 8",
            "Custom spatial autoregression Y=ρWY+Xβ+ε, concentrated ML, golden section search for ρ", "COMPLETED"),
        GapItem(19, "Propensity Score", "CausalInference (propensity.jl, ipw.jl)", 218,
            "CausalInference.jl", "HIGH", "Vol 11",
            "Custom logistic regression, HT/Hajek IPW, AIPW doubly-robust, overlap weighting, bootstrap SE", "COMPLETED"),
        GapItem(20, "Matching", "CausalInference (matching.jl)", 118,
            "CausalInference.jl", "HIGH", "Vol 11",
            "Custom greedy 1:k NN propensity matching with caliper, ATT estimation, SMD balance", "COMPLETED"),
        GapItem(21, "DiD / RDD", "PolicyEval (did.jl, rdd.jl)", 300,
            "CausalInference.jl", "HIGH", "Vol 11",
            "Custom 2x2 DiD, staggered DiD, local polynomial RDD, IK bandwidth, McCrary test", "COMPLETED"),
        GapItem(22, "p-Median / Covering", "FacilityLocation", 238,
            "JuMP.jl + HiGHS", "HIGH", "Vol 12",
            "Custom greedy p-median with 2-opt, greedy set cover, MCLP with random restarts", "COMPLETED"),
        GapItem(23, "Branch-and-Bound", "ResourceAllocation (branch_bound.jl)", 150,
            "JuMP.jl", "HIGH", "Vol 12",
            "Custom binary IP solver with LP relaxation — JuMP+HiGHS solves these exactly in milliseconds", "COMPLETED"),
        GapItem(24, "Decision Trees/RF", "HealthcareML (trees.jl, ensemble.jl)", 400,
            "MLJ.jl + DecisionTree.jl", "HIGH", "Vol 5",
            "Custom CART, random forest, gradient boosting, feature importance, SHAP-like explainability", "COMPLETED"),
        GapItem(25, "Disease Mapping", "DiseaseMapping (bym.jl, smr.jl)", 300,
            "Turing.jl + GeoStats.jl", "HIGH", "Vol 10",
            "Custom BYM model, empirical Bayes smoothing, SMR with Byar's CI", "COMPLETED"),
        GapItem(26, "Synthetic Control", "PolicyEval (synth_control.jl)", 150,
            "SyntheticControlMethods.jl", "MEDIUM", "Vol 11",
            "Custom synthetic control method with constrained optimization", "COMPLETED"),
        GapItem(27, "SGS Simulation", "GeostatHealth (simulation.jl)", 85,
            "GeoStats.jl", "MEDIUM", "Vol 10",
            "Custom sequential Gaussian simulation with local kriging", "COMPLETED"),
        GapItem(28, "Conformal Prediction", "ConformalHealth", 350,
            "ConformalPrediction.jl", "MEDIUM", "Vol 8",
            "Custom split conformal, jackknife+, CQR, classification conformal, calibration", "COMPLETED"),
        GapItem(29, "MDP / Value Iteration", "ResourceAllocation (mdp.jl)", 148,
            "POMDPs.jl", "MEDIUM", "Vol 12",
            "Custom value iteration, policy iteration for healthcare staffing MDP", "COMPLETED"),
        GapItem(30, "TSP / VRP", "HealthRouting (tsp.jl, vrp.jl)", 160,
            "JuMP.jl / TravelingSalesmanHeuristics.jl", "MEDIUM", "Vol 12",
            "Custom nearest-neighbor + 2-opt TSP, custom VRP with capacity constraints", "COMPLETED"),
        GapItem(31, "Point Patterns", "PointPatterns (ripley.jl, kde.jl)", 350,
            "GeoStats.jl + KernelDensity.jl", "MEDIUM", "Vol 10",
            "Custom Ripley's K/L, kernel density estimation, DBSCAN clustering", "COMPLETED"),
        GapItem(32, "STL Decomposition", "TemporalHealth (stl.jl)", 150,
            "SeasonalTrendLoess.jl", "MEDIUM", "Vol 5",
            "Custom seasonal-trend decomposition via LOESS", "COMPLETED"),
        GapItem(33, "Changepoint", "TemporalHealth (changepoint.jl)", 120,
            "Changepoints.jl", "MEDIUM", "Vol 5",
            "Custom PELT and binary segmentation for changepoint detection", "COMPLETED"),
        GapItem(34, "CUSUM / EWMA", "SurveillanceSystems (cusum.jl)", 165,
            "ControlCharts.jl", "LOW", "Vol 13",
            "Custom CUSUM/EWMA control charts — partially domain-specific", "COMPLETED"),
        GapItem(35, "Spatial DiD", "SpatialCausal (spatial_did.jl, conley.jl)", 250,
            "CausalInference.jl + Vcov.jl", "MEDIUM", "Vol 11",
            "Custom spatial DiD with spillover decomposition, Conley spatial SEs", "COMPLETED"),
    ]
end

function volume_summaries()
    return [
        VolumeSummary("GeoSpatialEngine", 0, 1, true,
            ["Uses GeoStats.jl, Flux.jl, MLJ, GeoInterface — EXEMPLARY"]),
        VolumeSummary("HealthcareGeo", 0, 1, true,
            ["Uses ArchGDAL, GeoStats, CairoMakie, GeoMakie — EXEMPLARY"]),
        VolumeSummary("healthcare_geo_workspace", 0, 3, true,
            ["Uses Turing.jl, GeoStats, NearestNeighbors — GOOD"]),
        VolumeSummary("Vol 4: Healthcare Platform", 350, 1, true,
            ["PointPatterns custom but Genie.jl API is correct"]),
        VolumeSummary("Vol 5: ML Production", 1400, 3, true,
            ["MIGRATED: DecisionTree.jl, Graphs.jl, StateSpaceModels.jl"]),
        VolumeSummary("Vol 6: Advanced Inference", 1200, 2, true,
            ["MIGRATED: AbstractGPs.jl, KernelFunctions.jl, Optim.jl"]),
        VolumeSummary("Vol 7: Deep Learning", 2600, 2, true,
            ["MIGRATED: Flux.jl + Zygote.jl, Turing.jl + MCMCChains"]),
        VolumeSummary("Vol 8: Equity & Spatial", 3200, 3, true,
            ["MIGRATED: Distances.jl, Optim.jl, StatsBase, Distributions"]),
        VolumeSummary("Vol 9: Survival/Networks/TS", 3700, 3, true,
            ["MIGRATED: Survival.jl, OrdinaryDiffEq, Graphs.jl, StateSpaceModels.jl"]),
        VolumeSummary("Vol 10: Geostatistics", 2600, 3, true,
            ["MIGRATED: GeoStats.jl, Variography, KernelDensity, Clustering.jl"]),
        VolumeSummary("Vol 11: Causal Inference", 1800, 3, true,
            ["MIGRATED: GLM.jl, NearestNeighbors.jl, Optim.jl"]),
        VolumeSummary("Vol 12: Optimization", 1650, 3, true,
            ["MIGRATED: JuMP.jl + HiGHS (exact IP solvers)"]),
        VolumeSummary("Vol 13: Epidemiology", 2100, 3, true,
            ["MIGRATED: OrdinaryDiffEq, Distributions.jl, StatsBase"]),
    ]
end

function sciml_packages()
    return [
        SciMLPackage("DifferentialEquations.jl", "ODE/SDE/Jump", "SciML", "Production",
            "Custom RK4, Euler, tau-leaping in epidemic models",
            "https://github.com/SciML/DifferentialEquations.jl"),
        SciMLPackage("Flux.jl", "Neural Networks", "SciML", "Production",
            "Custom Dense, BatchNorm, Dropout, training loops",
            "https://github.com/FluxML/Flux.jl"),
        SciMLPackage("Lux.jl", "Neural Networks", "SciML", "Production",
            "Alternative to Flux with explicit parameter management",
            "https://github.com/LuxDL/Lux.jl"),
        SciMLPackage("Zygote.jl", "Autodiff", "SciML", "Production",
            "Finite-difference numerical gradients",
            "https://github.com/FluxML/Zygote.jl"),
        SciMLPackage("Enzyme.jl", "Autodiff", "SciML", "Production",
            "Finite-difference numerical gradients",
            "https://github.com/EnzymeAD/Enzyme.jl"),
        SciMLPackage("Optimization.jl", "Optimization", "SciML", "Production",
            "Custom Nelder-Mead, golden section, gradient ascent",
            "https://github.com/SciML/Optimization.jl"),
        SciMLPackage("Turing.jl", "Bayesian/MCMC", "PPL", "Production",
            "Custom MH, HMC, VI, convergence diagnostics",
            "https://github.com/TuringLang/Turing.jl"),
        SciMLPackage("AbstractGPs.jl", "Gaussian Processes", "JuliaGPs", "Stable",
            "Custom GP regression and kernels",
            "https://github.com/JuliaGaussianProcesses/AbstractGPs.jl"),
        SciMLPackage("Survival.jl", "Survival Analysis", "JuliaStats", "Stable",
            "Custom Cox PH, Kaplan-Meier, Nelson-Aalen",
            "https://github.com/JuliaStats/Survival.jl"),
        SciMLPackage("Graphs.jl", "Graph Theory", "JuliaGraphs", "Production",
            "Custom adjacency list, Dijkstra, PageRank, betweenness",
            "https://github.com/JuliaGraphs/Graphs.jl"),
        SciMLPackage("GeoStats.jl", "Geostatistics", "GeoStats", "Production",
            "Custom kriging, variogram, SGS, point patterns",
            "https://github.com/JuliaEarth/GeoStats.jl"),
        SciMLPackage("JuMP.jl", "Math Programming", "MathOpt", "Production",
            "Custom p-median, branch-and-bound, set cover",
            "https://github.com/jump-dev/JuMP.jl"),
        SciMLPackage("MLJ.jl", "ML Framework", "Alan Turing Inst.", "Production",
            "Custom decision trees, random forest, ensemble",
            "https://github.com/alan-turing-institute/MLJ.jl"),
        SciMLPackage("StateSpaceModels.jl", "Time Series", "—", "Stable",
            "Custom ARIMA, Kalman filter, state space",
            "https://github.com/LAMPSPUC/StateSpaceModels.jl"),
        SciMLPackage("CausalInference.jl", "Causal Inference", "—", "Stable",
            "Custom propensity score, matching, IPW, DiD, RDD",
            "https://github.com/mschauer/CausalInference.jl"),
        SciMLPackage("POMDPs.jl", "MDP/RL", "JuliaPOMDP", "Stable",
            "Custom value iteration, policy iteration",
            "https://github.com/JuliaPOMDP/POMDPs.jl"),
        SciMLPackage("ConformalPrediction.jl", "Conformal", "—", "Stable",
            "Custom split conformal, jackknife+, CQR",
            "https://github.com/JuliaTrustworthyAI/ConformalPrediction.jl"),
    ]
end

function migration_phases()
    return [
        MigrationPhase(1, "Critical Infrastructure [DONE]", "Completed",
            ["[DONE] Replace custom RK4/Euler → OrdinaryDiffEq.jl (Tsit5)",
             "[DONE] Replace custom neural layers/backprop → Flux.jl + Optimisers.jl",
             "[DONE] Replace finite-diff gradients → Zygote.jl",
             "[DONE] Replace custom MH/HMC/VI → Turing.jl + MCMCChains"],
            "CRITICAL"),
        MigrationPhase(2, "Core Statistics [DONE]", "Completed",
            ["[DONE] Replace custom kriging/variogram → GeoStats.jl + Variography",
             "[DONE] Replace custom Cox/KM/NA → Survival.jl + Optim.jl",
             "[DONE] Replace custom graph algorithms → Graphs.jl",
             "[DONE] Replace custom ARIMA/Kalman → StateSpaceModels.jl"],
            "HIGH"),
        MigrationPhase(3, "Applied Methods [DONE]", "Completed",
            ["[DONE] Replace custom GWR → Distances.jl + Optim.jl",
             "[DONE] Replace custom causal inference → GLM.jl + NearestNeighbors",
             "[DONE] Replace custom GP → KernelFunctions.jl + Optim.jl",
             "[DONE] Replace custom optimization → JuMP.jl + HiGHS"],
            "HIGH"),
        MigrationPhase(4, "Refinements [DONE]", "Completed",
            ["[DONE] Replace custom conformal deps → StatsBase + Distributions",
             "[DONE] Replace custom decision trees → DecisionTree.jl",
             "[DONE] Replace custom MDP → cleaned up (kept custom)",
             "[DONE] Replace custom point patterns → Clustering.jl + KernelDensity"],
            "MEDIUM"),
    ]
end

function severity_counts()
    items = gap_items()
    counts = Dict{String,Int}()
    for item in items
        counts[item.severity] = get(counts, item.severity, 0) + 1
    end
    return counts
end

function total_custom_loc()
    return sum(item.custom_loc for item in gap_items())
end

function coverage_by_domain()
    items = gap_items()
    domains = Dict{String,Vector{GapItem}}()
    for item in items
        push!(get!(domains, item.domain, GapItem[]), item)
    end
    return domains
end

end # module
