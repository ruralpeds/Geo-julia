# Vol 8 Architecture Bootstrap Specification
## Health Equity, Spatial Regression & Conformal Prediction — Chapters 48–55

## Layout

```
vol8_equity_spatial/
├── packages/
│   ├── HealthEquity/              # Ch 48 — Fairness metrics & disparity analysis
│   │   └── src/
│   │       ├── metrics.jl          # Demographic parity, equalized odds, Theil/Gini
│   │       ├── disparities.jl      # Oaxaca-Blinder, concentration curves, inequity index
│   │       ├── fairness.jl         # Group threshold optimisation, Platt calibration by group
│   │       └── report.jl           # EquityReport with waterfall chart data
│   ├── SpatialRegression/         # Ch 49 — Local & global spatial regression models
│   │   └── src/
│   │       ├── gwr.jl              # Geographically Weighted Regression (Fotheringham 1996)
│   │       ├── spatial_lag.jl      # Spatial lag model Y = ρWY + Xβ + ε
│   │       ├── spatial_error.jl    # Spatial error model Y = Xβ + u, u = λWu + ε
│   │       ├── gwrf.jl             # Geographically Weighted Random Forest
│   │       └── diagnostics.jl      # Moran residuals, LM tests, Breusch-Pagan spatial
│   └── ConformalHealth/           # Ch 50 — Distribution-free uncertainty quantification
│       └── src/
│           ├── split_conformal.jl  # Split conformal prediction (Papadopoulos 2002)
│           ├── jackknife.jl        # Jackknife+ and CV+ conformal
│           ├── cqr.jl              # Conformalized Quantile Regression (Romano 2019)
│           ├── classification.jl   # RAPS adaptive prediction sets (Angelopoulos 2021)
│           └── calibration.jl      # Temperature scaling, isotonic regression, reliability
├── scripts/
│   ├── equity_dashboard.jl        # Interactive equity monitoring dashboard
│   ├── spatial_pipeline.jl        # End-to-end GWR + diagnostics + maps
│   └── conformal_suite.jl         # Comparative conformal coverage benchmarks
├── manuscript/
│   └── chapters/
│       ├── ch48_health_equity.qmd
│       ├── ch49_spatial_regression.qmd
│       └── ch50_conformal_prediction.qmd
├── test/
│   └── integration_test.jl        # 20 testsets
└── specs/
    └── vol8_bootstrap.md
```

## Key Algorithms

### HealthEquity.jl
- **Demographic parity**: |P(Ŷ=1|A=0) - P(Ŷ=1|A=1)| ≤ ε
- **Equalized odds**: |TPR_A0 - TPR_A1| + |FPR_A0 - FPR_A1|
- **Calibration gap**: |P(Y=1|Ŷ=p,A=0) - P(Y=1|Ŷ=p,A=1)| per probability bin
- **Theil index**: T = (1/n)Σ(y_i/ȳ)·log(y_i/ȳ); between/within decomposition
- **Concentration index**: C = (2/μ)Cov(y, r) where r = relative rank in SES
- **Oaxaca-Blinder decomposition**: Δȳ = (X̄_A - X̄_B)'β_B + X̄_B'(β_A - β_B)
- **Platt calibration by group**: logistic calibration on held-out group-stratified data
- **Threshold optimisation**: scan thresholds per group to equalise TPR or FPR

### SpatialRegression.jl
- **GWR**: β_i = (X'W_i X)⁻¹X'W_i y; W_i = diag(K(d_ij/b)) with Gaussian/bisquare kernel
- **Bandwidth**: AIC-c minimisation via golden section search
- **Spatial lag**: (I - ρW)y = Xβ + ε; LU-based spectral density for ML
- **Spatial error**: y = Xβ + u, u = λWu + ε; Prais-Winsten GLS iteration
- **LM tests**: LM_lag = (e'Wy/s²)² / T₁; LM_err = (e'We/s²)² / T₂
- **GW-RF**: bootstrap random forests with spatial kernel-weighted sampling

### ConformalHealth.jl
- **Split conformal**: calibration scores q̂ = ⌈(n+1)(1-α)/n⌉-th quantile of {s_i}
- **CQR**: q̂_lo(x) - q̂; prediction interval [q̂_lo - c, q̂_hi + c]
- **RAPS**: softmax scores; penalty λ for each additional class; adaptive set size
- **Jackknife+**: leave-one-out residuals; prediction interval via quantile of {ŷ_{-i} ± |r_i|}
- **Temperature scaling**: T* = argmin_T Σ NLL(σ(logits/T), y); single scalar calibration
- **Isotonic regression**: monotone step function fit on (p̂, y) via PAVA

## Dataset Context (North Dakota)

Vol 8 extends the ND healthcare access dataset with equity dimensions:
- Rural/urban status (RUCA codes)
- Racial/ethnic composition by county (ACS 5-year estimates)
- Insurance type (Medicare/Medicaid/private/uninsured)
- Socioeconomic status (poverty rate, median income)
- GWR reveals spatial non-stationarity in access-to-poverty relationship

*Vol 8 — Open-Source Healthcare GIS Textbook in Julia*
*Chapters 48–55 | Timothy Hartzog — 2026*
