# Vol 10 — Geostatistics, Bayesian Disease Mapping & Point Pattern Analysis

## Scope

Three production-ready pure-Julia packages at the heart of spatial
epidemiology and disease surveillance:

1. **GeostatHealth.jl** — Variogram estimation and modelling; ordinary/
   universal kriging; cross-validation; sequential Gaussian simulation
2. **DiseaseMapping.jl** — Standardised Mortality/Morbidity Ratios (SMR);
   Besag-York-Mollié (BYM) Bayesian disease mapping with ICAR prior;
   empirical Bayes smoothing; spatial scan statistic (Kulldorff)
3. **PointPatterns.jl** — Kernel density estimation with bandwidth selection;
   Ripley's K/L/G functions with Monte Carlo CSR envelopes; DBSCAN spatial
   clustering; Knox space-time clustering test; spatial scan statistic

## Package Architecture

### GeostatHealth.jl
- `src/variogram.jl`   — Empirical variogram (classical/robust); spherical/
                         exponential/Gaussian/Matérn model fitting (WLS)
- `src/kriging.jl`     — Simple kriging, ordinary kriging (SK/OK), universal
                         kriging (UK); kriging variance; leave-one-out CV
- `src/simulation.jl`  — Sequential Gaussian simulation (SGS); turning bands
- `src/report.jl`      — GeostatReport

### DiseaseMapping.jl
- `src/smr.jl`         — Indirect standardisation; SMR; Byar 95% CI; Poisson test
- `src/bym.jl`         — ICAR spatial prior (sparse precision); BYM (u+v);
                         Gibbs sampler; posterior mean/variance; DIC
- `src/smoothing.jl`   — Empirical Bayes (Marshall 1991); kernel smoother;
                         spatial scan (Kulldorff circular, Poisson LLR)
- `src/report.jl`      — DiseaseMappingReport

### PointPatterns.jl
- `src/kde.jl`         — 2-D Gaussian/Epanechnikov/quartic KDE; Silverman
                         rule-of-thumb; likelihood cross-validation bandwidth
- `src/ripley.jl`      — Ripley's K(r), L(r) = sqrt(K/π)-r, G(r) NND;
                         Monte Carlo CSR envelope; pcf (pair correlation)
- `src/clustering.jl`  — DBSCAN (Ester 1996); Knox test (space-time);
                         spatial scan statistic (circular window, Poisson LLR)
- `src/report.jl`      — PointPatternReport

## Chapters

- **Ch 54** — Geostatistics and Spatial Interpolation with Kriging
- **Ch 55** — Bayesian Disease Mapping: SMR to BYM
- **Ch 56** — Point Pattern Analysis: KDE, Ripley's Functions, and Clustering

## Pure-Julia Constraint

No GeoStats.jl, Distances.jl, or Distributions.jl dependencies.
All algorithms from scratch: variogram WLS, kriging system solve, Gibbs ICAR,
DBSCAN, K-function Monte Carlo.
