# Julia Healthcare GIS — Open Textbook

**A comprehensive, production-quality open textbook for geospatial healthcare analysis in Julia.**

## Overview

This textbook covers the full stack of geospatial healthcare analysis:
spatial access metrics, statistical inference, machine learning, and production deployment
— all implemented from scratch in Julia.

## Volumes

| Volume | Chapters | Focus |
|--------|----------|-------|
| **Vol 1** | 1–15 | Core geospatial: Census API, geocoding, E2SFCA, choropleth maps |
| **Vol 2** | 16–22 | Extended analysis: multi-state, advanced access, regression |
| **Vol 3** | 23–25 | Package ecosystem: SpatialStats.jl, Geocode.jl, MapClassify.jl, Overpass.jl |
| **Vol 4** | 26–34 | Healthcare platform: PointPatterns.jl, Bayesian GLMs, ND pipeline, GPU |
| **Vol 5** | 35–42 | ML & production: HealthcareML.jl, NetworkHealth.jl, federated learning |

## Quick Start

```julia
# Install Vol 3 packages
import Pkg
Pkg.develop(path="julia_geo_packages/packages/SpatialStats")
using SpatialStats

# Compute Moran's I
W = queen_weights(county_df)
result = moran(poverty_rates, W; permutations=999)
println("I = $(result.I), p = $(result.p_value)")
```

```julia
# ML-based access prediction (Vol 5)
using HealthcareML

feat = build_features(county_df, :access_score)
model = RandomForestAccess(n_trees=100, max_depth=6)
fit!(model, feat.X, feat.y)

report = generate_report(model, feat.X, feat.y, feat.feature_names)
show(report)
```

## Key Algorithms

- **E2SFCA**: Enhanced Two-Step Floating Catchment Area (Luo & Wang 2003)
- **Moran's I**: Global and local spatial autocorrelation (Moran 1950, Anselin 1995)
- **Ripley's K**: Point pattern analysis with edge correction (Ripley 1976)
- **CART / Random Forest / GBM**: Pure-Julia tree ensembles (Breiman 2001)
- **Kernel SHAP**: Approximate Shapley values (Lundberg & Lee 2017)
- **PELT**: Optimal changepoint detection (Killick et al. 2012)
- **FedAvg + FedProx**: Federated learning (McMahan et al. 2017; Li et al. 2020)
- **Louvain**: Community detection (Blondel et al. 2008)

## Citation

```bibtex
@book{hartzog2026julia,
  title     = {Julia Healthcare GIS: An Open Textbook},
  author    = {Hartzog, Timothy},
  year      = {2026},
  url       = {https://timothyhartzog.github.io/geo-julia},
  note      = {Volumes 1--5, Chapters 1--42}
}
```
