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
            "Custom Dense, BatchNorm, Dropout, MultiHeadAttention, ResidualBlock layers with He/Glorot init", "NOT STARTED"),
        GapItem(2, "Deep Learning", "DeepHealth (training.jl)", 363,
            "Flux.jl + Optimisers.jl", "CRITICAL", "Vol 7",
            "Custom Adam, SGD+momentum, backpropagation, loss functions, mini-batch iterator, early stopping, cosine annealing", "NOT STARTED"),
        GapItem(3, "Automatic Differentiation", "DeepHealth (training.jl)", 80,
            "Zygote.jl / Enzyme.jl", "CRITICAL", "Vol 7",
            "Finite-difference numerical gradients for all parameter updates — O(n) per param, prone to numerical error", "NOT STARTED"),
        GapItem(4, "MCMC Sampling", "BayesianHealth (mcmc.jl)", 334,
            "Turing.jl + AdvancedMCMC.jl", "CRITICAL", "Vol 7",
            "Custom Metropolis-Hastings with dual-averaging, HMC with leapfrog integrator, Chains struct, R-hat, ESS", "NOT STARTED"),
        GapItem(5, "Variational Inference", "BayesianHealth (vi.jl)", 209,
            "Turing.jl + AdvancedVI.jl", "CRITICAL", "Vol 7",
            "Custom mean-field Gaussian VI, ELBO via reparameterization, Adam ascent, posterior predictive", "NOT STARTED"),
        GapItem(6, "ODE Integration", "NetworkHealth (epidemic.jl)", 309,
            "DifferentialEquations.jl", "CRITICAL", "Vol 9",
            "Custom RK4 integrator for SIR/SEIR/SEIRD compartmental models, stochastic tau-leaping network SIR", "NOT STARTED"),
        GapItem(7, "ODE Integration", "InfectiousDisease (compartmental.jl)", 182,
            "DifferentialEquations.jl", "CRITICAL", "Vol 13",
            "Custom Euler + RK4 for SIR/SEIR, stochastic SIR with custom Poisson tau-leaping", "NOT STARTED"),
        GapItem(8, "Gaussian Processes", "GaussianProcessHealth", 400,
            "AbstractGPs.jl + KernelFunctions.jl", "HIGH", "Vol 6",
            "Custom exact GP regression, kernel matrix computation, sparse GP, hyperparameter optimization", "NOT STARTED"),
        GapItem(9, "Cox PH Model", "SurvivalAnalysis (cox.jl)", 226,
            "Survival.jl", "HIGH", "Vol 9",
            "Custom Breslow partial likelihood, Newton-Raphson, baseline hazard, Harrell's C-statistic", "NOT STARTED"),
        GapItem(10, "Kaplan-Meier", "SurvivalAnalysis (estimators.jl)", 279,
            "Survival.jl", "HIGH", "Vol 9",
            "Custom KM product-limit, Greenwood variance, Nelson-Aalen, log-rank test, RMST", "NOT STARTED"),
        GapItem(11, "Parametric Survival", "SurvivalAnalysis (parametric.jl)", 200,
            "Survival.jl", "HIGH", "Vol 9",
            "Custom Weibull/Exponential/Log-logistic AFT MLE with finite-difference Hessian", "NOT STARTED"),
        GapItem(12, "Graph Algorithms", "NetworkHealth (graph.jl)", 288,
            "Graphs.jl", "HIGH", "Vol 9",
            "Custom adjacency list, Dijkstra, BFS, PageRank, betweenness centrality, clustering coefficient", "NOT STARTED"),
        GapItem(13, "ARIMA", "TimeSeriesHealth (arima.jl)", 251,
            "StateSpaceModels.jl", "HIGH", "Vol 9",
            "Custom ACF/PACF, Yule-Walker AR, ARMA likelihood via innovations, auto-ARIMA grid search", "NOT STARTED"),
        GapItem(14, "Kalman Filter", "TimeSeriesHealth (state_space.jl)", 233,
            "StateSpaceModels.jl / Kalman.jl", "HIGH", "Vol 9",
            "Custom Kalman filter/RTS smoother, EM for local-level DLM, local trend model, h-step forecast", "NOT STARTED"),
        GapItem(15, "Variogram Fitting", "GeostatHealth (variogram.jl)", 248,
            "GeoStats.jl", "HIGH", "Vol 10",
            "Custom empirical variogram (Matheron + Cressie-Hawkins), spherical/exponential/Gaussian/Matern models, Nelder-Mead WLS fit", "NOT STARTED"),
        GapItem(16, "Kriging", "GeostatHealth (kriging.jl)", 261,
            "GeoStats.jl", "HIGH", "Vol 10",
            "Custom Simple/Ordinary/Universal kriging with LOO cross-validation", "NOT STARTED"),
        GapItem(17, "GWR", "SpatialRegression (gwr.jl)", 311,
            "GeoStats.jl + SpatialDependence.jl", "HIGH", "Vol 8",
            "Custom GWR with Gaussian/bisquare/Epanechnikov kernels, Haversine distances, AICc bandwidth selection", "NOT STARTED"),
        GapItem(18, "Spatial Lag/Error", "SpatialRegression (spatial_lag.jl)", 158,
            "SpatialDependence.jl", "HIGH", "Vol 8",
            "Custom spatial autoregression Y=ρWY+Xβ+ε, concentrated ML, golden section search for ρ", "NOT STARTED"),
        GapItem(19, "Propensity Score", "CausalInference (propensity.jl, ipw.jl)", 218,
            "CausalInference.jl", "HIGH", "Vol 11",
            "Custom logistic regression, HT/Hajek IPW, AIPW doubly-robust, overlap weighting, bootstrap SE", "NOT STARTED"),
        GapItem(20, "Matching", "CausalInference (matching.jl)", 118,
            "CausalInference.jl", "HIGH", "Vol 11",
            "Custom greedy 1:k NN propensity matching with caliper, ATT estimation, SMD balance", "NOT STARTED"),
        GapItem(21, "DiD / RDD", "PolicyEval (did.jl, rdd.jl)", 300,
            "CausalInference.jl", "HIGH", "Vol 11",
            "Custom 2x2 DiD, staggered DiD, local polynomial RDD, IK bandwidth, McCrary test", "NOT STARTED"),
        GapItem(22, "p-Median / Covering", "FacilityLocation", 238,
            "JuMP.jl + HiGHS", "HIGH", "Vol 12",
            "Custom greedy p-median with 2-opt, greedy set cover, MCLP with random restarts", "NOT STARTED"),
        GapItem(23, "Branch-and-Bound", "ResourceAllocation (branch_bound.jl)", 150,
            "JuMP.jl", "HIGH", "Vol 12",
            "Custom binary IP solver with LP relaxation — JuMP+HiGHS solves these exactly in milliseconds", "NOT STARTED"),
        GapItem(24, "Decision Trees/RF", "HealthcareML (trees.jl, ensemble.jl)", 400,
            "MLJ.jl + DecisionTree.jl", "HIGH", "Vol 5",
            "Custom CART, random forest, gradient boosting, feature importance, SHAP-like explainability", "NOT STARTED"),
        GapItem(25, "Disease Mapping", "DiseaseMapping (bym.jl, smr.jl)", 300,
            "Turing.jl + GeoStats.jl", "HIGH", "Vol 10",
            "Custom BYM model, empirical Bayes smoothing, SMR with Byar's CI", "NOT STARTED"),
        GapItem(26, "Synthetic Control", "PolicyEval (synth_control.jl)", 150,
            "SyntheticControlMethods.jl", "MEDIUM", "Vol 11",
            "Custom synthetic control method with constrained optimization", "NOT STARTED"),
        GapItem(27, "SGS Simulation", "GeostatHealth (simulation.jl)", 85,
            "GeoStats.jl", "MEDIUM", "Vol 10",
            "Custom sequential Gaussian simulation with local kriging", "NOT STARTED"),
        GapItem(28, "Conformal Prediction", "ConformalHealth", 350,
            "ConformalPrediction.jl", "MEDIUM", "Vol 8",
            "Custom split conformal, jackknife+, CQR, classification conformal, calibration", "NOT STARTED"),
        GapItem(29, "MDP / Value Iteration", "ResourceAllocation (mdp.jl)", 148,
            "POMDPs.jl", "MEDIUM", "Vol 12",
            "Custom value iteration, policy iteration for healthcare staffing MDP", "NOT STARTED"),
        GapItem(30, "TSP / VRP", "HealthRouting (tsp.jl, vrp.jl)", 160,
            "JuMP.jl / TravelingSalesmanHeuristics.jl", "MEDIUM", "Vol 12",
            "Custom nearest-neighbor + 2-opt TSP, custom VRP with capacity constraints", "NOT STARTED"),
        GapItem(31, "Point Patterns", "PointPatterns (ripley.jl, kde.jl)", 350,
            "GeoStats.jl + KernelDensity.jl", "MEDIUM", "Vol 10",
            "Custom Ripley's K/L, kernel density estimation, DBSCAN clustering", "NOT STARTED"),
        GapItem(32, "STL Decomposition", "TemporalHealth (stl.jl)", 150,
            "SeasonalTrendLoess.jl", "MEDIUM", "Vol 5",
            "Custom seasonal-trend decomposition via LOESS", "NOT STARTED"),
        GapItem(33, "Changepoint", "TemporalHealth (changepoint.jl)", 120,
            "Changepoints.jl", "MEDIUM", "Vol 5",
            "Custom PELT and binary segmentation for changepoint detection", "NOT STARTED"),
        GapItem(34, "CUSUM / EWMA", "SurveillanceSystems (cusum.jl)", 165,
            "ControlCharts.jl", "LOW", "Vol 13",
            "Custom CUSUM/EWMA control charts — partially domain-specific", "NOT STARTED"),
        GapItem(35, "Spatial DiD", "SpatialCausal (spatial_did.jl, conley.jl)", 250,
            "CausalInference.jl + Vcov.jl", "MEDIUM", "Vol 11",
            "Custom spatial DiD with spillover decomposition, Conley spatial SEs", "NOT STARTED"),
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
        VolumeSummary("Vol 5: ML Production", 1400, 3, false,
            ["Custom decision trees/RF", "Custom ARIMA/STL", "Custom graph algorithms"]),
        VolumeSummary("Vol 6: Advanced Inference", 1200, 2, false,
            ["Custom GP regression", "Custom causal inference (DiD, IV, RDD)"]),
        VolumeSummary("Vol 7: Deep Learning", 2600, 2, false,
            ["Custom neural networks + backprop", "Custom MCMC (MH, HMC) + VI"]),
        VolumeSummary("Vol 8: Equity & Spatial", 3200, 3, false,
            ["Custom GWR + spatial regression", "Custom conformal prediction", "Custom equity metrics"]),
        VolumeSummary("Vol 9: Survival/Networks/TS", 3700, 3, false,
            ["Custom Cox/KM/NA survival", "Custom graph + epidemic ODE", "Custom ARIMA/Kalman"]),
        VolumeSummary("Vol 10: Geostatistics", 2600, 3, false,
            ["Custom kriging (SK/OK/UK)", "Custom variogram fitting", "Custom point patterns"]),
        VolumeSummary("Vol 11: Causal Inference", 1800, 3, false,
            ["Custom propensity/IPW/AIPW", "Custom DiD/RDD", "Custom synthetic control"]),
        VolumeSummary("Vol 12: Optimization", 1650, 3, false,
            ["Custom p-median/covering", "Custom branch-and-bound", "Custom TSP/VRP"]),
        VolumeSummary("Vol 13: Epidemiology", 2100, 3, false,
            ["Custom SIR/SEIR ODE", "Custom CUSUM/EWMA", "Custom risk scoring"]),
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
        MigrationPhase(1, "Critical Infrastructure", "Weeks 1–3",
            ["Replace custom RK4/Euler → DifferentialEquations.jl",
             "Replace custom neural layers/backprop → Flux.jl or Lux.jl",
             "Replace finite-diff gradients → Zygote.jl",
             "Replace custom MH/HMC/VI → Turing.jl"],
            "CRITICAL"),
        MigrationPhase(2, "Core Statistics", "Weeks 4–6",
            ["Replace custom kriging/variogram → GeoStats.jl",
             "Replace custom Cox/KM/NA → Survival.jl",
             "Replace custom graph algorithms → Graphs.jl",
             "Replace custom ARIMA/Kalman → StateSpaceModels.jl"],
            "HIGH"),
        MigrationPhase(3, "Applied Methods", "Weeks 7–9",
            ["Replace custom GWR → GeoStats.jl",
             "Replace custom causal inference → CausalInference.jl",
             "Replace custom GP → AbstractGPs.jl",
             "Replace custom optimization → JuMP.jl"],
            "HIGH"),
        MigrationPhase(4, "Refinements", "Weeks 10–12",
            ["Replace custom conformal prediction → ConformalPrediction.jl",
             "Replace custom decision trees → MLJ.jl",
             "Replace custom MDP → POMDPs.jl",
             "Replace custom point patterns → GeoStats.jl"],
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
