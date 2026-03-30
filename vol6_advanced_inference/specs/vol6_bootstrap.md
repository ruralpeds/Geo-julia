# Vol 6 Architecture Bootstrap Specification
## Advanced Inference & MLOps — Chapters 43–50

## Layout

```
vol6_advanced_inference/
├── packages/
│   ├── CausalHealth/            # Ch 43 — DiD, Synthetic Control, IV, RDD
│   │   └── src/
│   │       ├── did.jl            # TWFE DiD + event study + parallel trends test
│   │       ├── synthetic_control.jl  # Abadie et al. 2010, projected GD, placebos
│   │       ├── iv.jl             # 2SLS, HC3 SE, Hausman, Sargan
│   │       ├── rdd.jl            # Local poly RD, CCT bandwidth, fuzzy RD
│   │       └── report.jl         # CausalReport, causal_summary
│   └── GaussianProcessHealth/   # Ch 44 — GP regression + UQ
│       └── src/
│           ├── kernels.jl        # SE, Matérn 3/2, 5/2, RQ, OU, Composite
│           ├── gp_regression.jl  # Exact GP (Cholesky), type-II ML, Nelder-Mead
│           ├── sparse_gp.jl      # FITC sparse GP (Snelson & Ghahramani 2006)
│           └── spatial.jl        # surface grid, uncertainty map, exceedance prob
├── scripts/
│   ├── mlops_pipeline.jl        # Ch 46 — model registry, KS drift, PSI, A/B test
│   └── multimodal_integration.jl # Ch 47 — geo + claims + network fusion, BMA
├── manuscript/
│   └── chapters/
│       ├── ch43_causal_inference.qmd
│       └── ch44_gaussian_processes.qmd
├── test/
│   └── integration_test.jl      # Ch 48.2 — 20 testsets
└── specs/
    └── vol6_bootstrap.md
```

## Key Algorithms

### CausalHealth.jl
- **TWFE DiD**: two-way FE via within-unit + within-time demeaning; HC3 robust SE
- **Event Study**: rel_time dummies, reference period t=-1
- **Parallel Trends**: F-test on treated × pre-period interactions
- **Synthetic Control**: projected gradient descent (Dykstra's simplex projection)
- **2SLS**: first stage → second stage; HC3 sandwich; Hausman Wu-Hausman; Sargan J
- **RDD**: local polynomial (p=1 default); triangular kernel; CCT rule-of-thumb bandwidth
- **Fuzzy RDD**: Wald estimator τ_Y / τ_D

### GaussianProcessHealth.jl
- **Exact GP**: Cholesky O(n³); posterior mean/variance; log marginal likelihood
- **Type-II ML**: Nelder-Mead simplex over log-transformed hyperparameters
- **FITC Sparse GP**: Woodbury identity; ELBO; inducing at random training points
- **LOO-CV**: Exact formula via K_inv diagonal; no re-fitting
- **Exceedance probability**: P(f > threshold | y) via Gaussian tail

### MLOps (scripts/mlops_pipeline.jl)
- **Model registry**: versioned records, champion/challenger, leaderboard
- **KS drift**: two-sample KS, asymptotic p-value 2exp(-2c²)
- **PSI**: Population Stability Index, quantile bins from reference
- **A/B test**: Welch's t-test; power via Cohen's d
- **Retraining trigger**: PSI + relative RMSE increase + min samples

## Identification Strategy Selector

| Design | CausalHealth function | Key assumption |
|--------|----------------------|----------------|
| Staggered policy rollout | `did_estimate` | Parallel trends |
| Single treated region | `synthetic_control` | Matching pre-trend |
| Geographic instrument | `iv_2sls` | Exclusion restriction |
| Income/eligibility cutoff | `rd_estimate` | Local continuity |

*Vol 6 — Open-Source Healthcare GIS Textbook in Julia*
*Chapters 43–50 | Timothy Hartzog — 2026*
