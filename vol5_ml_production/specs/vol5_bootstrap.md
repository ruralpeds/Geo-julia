# Vol 5 Architecture Bootstrap Specification
## Julia Healthcare ML & Production Platform — Chapters 35–42

---

## Repository Layout

```
vol5_ml_production/
├── packages/
│   ├── HealthcareML/            # Ch 35 — ML for access prediction
│   │   ├── Project.toml
│   │   └── src/
│   │       ├── HealthcareML.jl
│   │       ├── features.jl       # AccessFeatures, build_features
│   │       ├── trees.jl          # RidgeAccess, DecisionTreeAccess
│   │       ├── ensemble.jl       # RandomForestAccess, GradientBoostAccess
│   │       ├── explainability.jl # SHAP, permutation importance, PDP
│   │       ├── validation.jl     # cross_validate, tune_hyperparameters
│   │       └── report.jl         # HealthcareMLReport, generate_report
│   ├── NetworkHealth/           # Ch 36 — Provider referral network analysis
│   │   ├── Project.toml
│   │   └── src/
│   │       ├── NetworkHealth.jl
│   │       ├── graph.jl          # ReferralNetwork, from_dataframe
│   │       ├── centrality.jl     # degree, betweenness, closeness, PageRank
│   │       ├── community.jl      # Louvain, label propagation
│   │       ├── flow.jl           # Ford-Fulkerson, referral concentration
│   │       └── access_metrics.jl # NetworkSummary, isolation, fragmentation
│   └── TemporalHealth/          # Ch 37 — Time series of health outcomes
│       ├── Project.toml
│       └── src/
│           ├── TemporalHealth.jl
│           ├── types.jl          # HealthTimeSeries, from_dataframe
│           ├── stl.jl            # STL decomposition, Holt-Winters
│           ├── arima.jl          # ARIMA(p,d,q), cross-correlation
│           ├── changepoint.jl    # PELT optimal changepoint detection
│           └── panel.jl          # panel_summary, panel_detrend, panel_fe
├── scripts/
│   ├── federated_learning.jl    # Ch 38 — FedAvg, FedProx, DP Gaussian
│   └── database_integration.jl  # Ch 39 — PostgreSQL + PostGIS (LibPQ.jl)
├── dashboard/
│   └── realtime_app.jl          # Ch 40 — WebSocket/SSE live updates
├── reports/
│   └── healthcare_report_template.qmd  # Ch 41.1 — Quarto auto-report
├── docs/
│   ├── make.jl                  # Documenter.jl site builder
│   └── src/
│       └── index.md             # Landing page
├── test/
│   └── integration_test.jl      # Ch 41.2 — 20 testsets
└── specs/
    └── vol5_bootstrap.md        # (this file)
```

---

## Chapter Map

| Chapter | File | Content |
|---------|------|---------|
| 35.1 | `packages/HealthcareML/src/features.jl` | Feature engineering: spatial lag, polynomial, interactions |
| 35.2 | `packages/HealthcareML/src/trees.jl` | Ridge regression, CART decision tree |
| 35.3 | `packages/HealthcareML/src/ensemble.jl` | Random Forest (OOB scoring), Gradient Boosting |
| 35.4 | `packages/HealthcareML/src/explainability.jl` | Kernel SHAP, permutation importance, PDP |
| 35.5 | `packages/HealthcareML/src/validation.jl` | k-fold CV, grid search, calibration |
| 35.6 | `packages/HealthcareML/src/report.jl` | Automated ML report generation |
| 36.1 | `packages/NetworkHealth/src/graph.jl` | ReferralNetwork data structure |
| 36.2 | `packages/NetworkHealth/src/centrality.jl` | Brandes betweenness, PageRank, eigenvector |
| 36.3 | `packages/NetworkHealth/src/community.jl` | Louvain modularity, label propagation |
| 36.4 | `packages/NetworkHealth/src/flow.jl` | Ford-Fulkerson, HHI, shortest paths |
| 36.5 | `packages/NetworkHealth/src/access_metrics.jl` | NetworkSummary, isolation index |
| 37.1 | `packages/TemporalHealth/src/types.jl` | HealthTimeSeries |
| 37.2 | `packages/TemporalHealth/src/stl.jl` | STL + Holt-Winters |
| 37.3 | `packages/TemporalHealth/src/arima.jl` | ARIMA(p,d,q) + cross-correlation |
| 37.4 | `packages/TemporalHealth/src/changepoint.jl` | PELT |
| 37.5 | `packages/TemporalHealth/src/panel.jl` | Two-way FE panel regression |
| 38 | `scripts/federated_learning.jl` | FedAvg + FedProx + DP Gaussian mechanism |
| 39 | `scripts/database_integration.jl` | PostGIS spatial queries + materialised views |
| 40 | `dashboard/realtime_app.jl` | SSE live updates, thread-safe state store |
| 41.1 | `reports/healthcare_report_template.qmd` | Quarto automated report |
| 41.2 | `test/integration_test.jl` | 20 cross-package testsets |
| 42 | `docs/` | Documenter.jl cross-volume site |

---

## Key Algorithms

### HealthcareML.jl
- **CART**: Variance-reduction splitting, `O(np log n)` per tree
- **Random Forest**: Bootstrap + random subspace, OOB error
- **GBM**: Friedman (2001) squared-error; shrinkage + subsampling
- **Kernel SHAP**: Lundberg & Lee (2017) weighted linear regression over coalition space
- **Permutation importance**: Breiman (2001) mean decrease in accuracy

### NetworkHealth.jl
- **Betweenness**: Brandes (2001) O(VE) algorithm
- **PageRank**: Power iteration with dangling node handling
- **Louvain**: Blondel et al. (2008) modularity maximisation Q = Σ[A_{ij} - k_i·k_j/2m]·δ(c_i,c_j)
- **Ford-Fulkerson**: Edmonds-Karp (BFS augmenting paths) O(VE²)

### TemporalHealth.jl
- **STL**: Cleveland et al. (1990) LOESS seasonal-trend decomposition
- **ARIMA**: Yule-Walker AR coefficients + innovations MA(q)
- **PELT**: Killick et al. (2012) O(n) optimal changepoint detection
- **Panel FE**: Two-way within estimator (unit + time demeaning)

### Federated Learning
- **FedAvg**: McMahan et al. (2017) weighted average of local updates
- **FedProx**: Li et al. (2020) proximal term `μ/2 ||w - w_global||²`
- **DP Gaussian**: σ = √(2ln(1.25/δ)) · C/ε; advanced composition for R rounds

---

## Registry Submission Checklist

### HealthcareML.jl
- [ ] `Project.toml`: name, uuid, version=0.1.0, julia ≥ 1.10
- [ ] 18 unit testsets passing on Julia 1.10 + 1.11
- [ ] No external ML framework dependency (pure Julia)
- [ ] `README.md` with quick-start, benchmark table

### NetworkHealth.jl
- [ ] 20 unit testsets passing
- [ ] Sparse matrix backend (SparseArrays.jl stdlib only)
- [ ] Benchmark against LightGraphs.jl / Graphs.jl

### TemporalHealth.jl
- [ ] 15 unit testsets passing
- [ ] Comparison table vs R's `forecast` package (ARIMA, HW)
- [ ] Panel FE validated against R `plm` package

---

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `POSTGRES_URL` | PostgreSQL connection string (Ch 39) |
| `ANTHROPIC_API_KEY` | Claude API for report generation |
| `JULIA_NUM_THREADS` | Parallelism for permutation tests / RF |

---

*Vol 5 — Open-Source Healthcare GIS Textbook in Julia*
*Chapters 35–42 | Timothy Hartzog — 2026*
