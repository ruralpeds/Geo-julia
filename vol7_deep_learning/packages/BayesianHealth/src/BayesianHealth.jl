"""
    BayesianHealth

Bayesian inference tools for healthcare data analysis.
Chapter 46 — Open-Source Healthcare GIS Textbook in Julia.

Provides pure-Julia implementations of:
- Variational Inference: Mean-field Gaussian VI, ELBO optimisation, reparameterization
- MCMC: Metropolis-Hastings, Hamiltonian Monte Carlo (leapfrog integrator)
- Model comparison: WAIC, LOO-IC (PSIS), Bayes factor
- Health priors: domain-informed prior distributions for healthcare data
- Convergence diagnostics: R-hat, ESS, trace summaries
"""
module BayesianHealth

using LinearAlgebra, Statistics, Random, DataFrames, Distributions

include("priors.jl")
include("vi.jl")
include("mcmc.jl")
include("model_comparison.jl")

export
    # Priors
    HealthPrior, rate_prior, cost_prior, proportion_prior,
    access_score_prior, prior_predictive_check,
    # VI
    MeanFieldGaussian, vi_fit, elbo,
    VIResult, vi_predict,
    # MCMC
    MetropolisHastings, HMCSampler,
    Chains, sample_chains,
    r_hat, ess, chain_summary,
    # Model comparison
    waic, loo_ic, bayes_factor,
    ModelComparison, compare_models_bayes

end # module
