# Vol 4 Architecture Bootstrap Specification
## Julia Healthcare GIS Platform — Chapters 26–34

> This document guides a fresh install of the Vol 4 platform from scratch.
> See `BUILD_EVERYTHING.md` for the master multi-volume build program.

---

## Repository Layout

```
vol4_healthcare_platform/
├── packages/
│   └── PointPatterns/          # Ch 26 — spatstat equivalent
│       ├── Project.toml
│       └── src/
│           ├── PointPatterns.jl
│           ├── types.jl         # PointPattern, RectWindow, PolyWindow
│           ├── kfunction.jl     # Ripley's K with edge correction
│           ├── gfunction.jl     # G/F/J functions
│           ├── csr_tests.jl     # Quadrat test, Clark-Evans
│           ├── intensity.jl     # Kernel intensity, adaptive bandwidth
│           ├── nearest.jl       # nndist, crossdist
│           └── scan.jl          # Kulldorff spatial scan
├── scripts/
│   ├── spatial_glm.jl           # Ch 27 — Bayesian spatial GLMs via Turing.jl
│   ├── advanced_cartography.jl  # Ch 28 — bivariate, dorling, kriging
│   └── gpu_acceleration.jl      # Ch 33 — CUDA.jl / Metal.jl
├── pipeline/
│   ├── 01_acquire_data.jl       # Ch 29.1.1 — TIGER, ACS, AHRF, NPPES
│   ├── 02_prepare_spatial.jl    # Ch 29.1.2 — geocode, build analysis dataset
│   ├── 03_spatial_analysis.jl   # Ch 29.1.3 — E2SFCA, Moran, LISA, SLM
│   └── 04_visualize.jl          # Ch 29.1.4 — 4-panel atlas, K-function plot
├── notebooks/
│   └── healthcare_dashboard.jl  # Ch 30 — Pluto.jl reactive dashboard
├── web/
│   ├── app.jl                   # Ch 31.1 — Genie.jl REST API
│   └── Dockerfile               # Ch 31.2 — containerized deployment
├── test/
│   └── integration_test.jl      # Ch 34.2 — cross-package integration tests
└── specs/
    ├── vol4_bootstrap.md        # (this file)
    └── BUILD_EVERYTHING.md      # master 8-phase build program
```

---

## Dependencies

### Julia (≥ 1.10)

**Standard ecosystem packages** (from General registry):

| Package | Version | Purpose |
|---------|---------|---------|
| Genie | ≥ 5.0 | Web framework |
| DataFrames | ≥ 1.6 | Tabular data |
| CSV | ≥ 0.10 | CSV I/O |
| JSON3 | ≥ 1.13 | JSON serialization |
| NearestNeighbors | ≥ 0.4 | kNN queries |
| Distributions | ≥ 0.25 | Statistical distributions |
| Statistics | stdlib | Mean, std, quantile |
| SparseArrays | stdlib | Sparse weight matrices |
| Serialization | stdlib | JLS binary cache |
| HTTP | ≥ 1.10 | HTTP client (geocoding, API) |
| PackageCompiler | ≥ 2.1 | Sysimage creation |

**Optional packages** (graceful fallback if absent):

| Package | Purpose | Fallback |
|---------|---------|---------|
| CairoMakie + GeoMakie | Static maps | Skipped |
| WGLMakie | Interactive maps (Pluto) | Static images |
| Pluto | Reactive notebook | Export to HTML |
| Turing | Bayesian MCMC | Frequentist IRLS |
| CUDA | NVIDIA GPU | CPU path |
| Metal | Apple Silicon GPU | CPU path |
| ArchGDAL | GDAL bindings | Missing geometry support |
| Shapefile | TIGER shapefiles | Synthetic centroids |
| GeoStats | Variogram + kriging | Skipped |

**Vol 3 local packages** (path-based):

| Package | Location |
|---------|----------|
| SpatialStats | `julia_geo_packages/packages/SpatialStats` |
| Geocode | `julia_geo_packages/packages/Geocode` |
| MapClassify | `julia_geo_packages/packages/MapClassify` |
| Overpass | `julia_geo_packages/packages/Overpass` |

---

## Quick Start

### 1. Install Julia 1.10+

```bash
curl -fsSL https://install.julialang.org | sh
```

### 2. Clone repository

```bash
git clone https://github.com/timothyhartzog/geo-julia.git
cd geo-julia
```

### 3. Install Vol 3 packages

```bash
cd julia_geo_packages
julia --project=. -e 'import Pkg; Pkg.instantiate()'
```

### 4. Install Vol 4 packages

```bash
cd vol4_healthcare_platform
julia --project=. -e 'import Pkg; Pkg.instantiate()'
```

### 5. Run integration tests

```bash
julia --project=. test/integration_test.jl
```

### 6. Run the ND pipeline (with synthetic data)

```bash
julia --project=. pipeline/04_visualize.jl
```

### 7. Launch the dashboard

```bash
julia -e 'using Pluto; Pluto.run(notebook="notebooks/healthcare_dashboard.jl")'
```

### 8. Start the web API

```bash
julia --project=. web/app.jl
# Test: curl http://localhost:8080/api/health | jq
```

### 9. Docker deployment

```bash
cd vol4_healthcare_platform/web
docker build -t healthcare-geo:latest .
docker run -p 8080:8080 healthcare-geo:latest
```

---

## Environment Variables

| Variable | Default | Required |
|----------|---------|---------|
| `CENSUS_API_KEY` | `""` | For real ACS data acquisition |
| `ANTHROPIC_API_KEY` | `""` | For AI interpretation in dashboard |
| `JULIA_NUM_THREADS` | `auto` | Parallelism for permutation tests |
| `GENIE_ENV` | `production` | Genie web framework mode |

---

## Data Sources

All network calls have synthetic fallbacks for offline/CI use.

| Dataset | Source | Fallback |
|---------|--------|---------|
| ND county boundaries | Census TIGER/Line | Synthetic centroids |
| ACS demographic data | Census API | Synthetic poverty/uninsurance |
| AHRF physician data | HRSA | Synthetic 200 providers |
| NPPES provider locations | CMS API | Synthetic 30 providers |
| OSM healthcare POIs | Overpass API | Skipped |

---

## Chapter Map

| Chapter | File | Content |
|---------|------|---------|
| 26 | `packages/PointPatterns/` | PointPatterns.jl — complete spatstat port |
| 27 | `scripts/spatial_glm.jl` | Bayesian spatial Poisson/NegBin/Logistic |
| 28 | `scripts/advanced_cartography.jl` | Bivariate, Dorling, kriging |
| 29.1.1 | `pipeline/01_acquire_data.jl` | TIGER, ACS, AHRF, NPPES |
| 29.1.2 | `pipeline/02_prepare_spatial.jl` | Geocoding, spatial join |
| 29.1.3 | `pipeline/03_spatial_analysis.jl` | E2SFCA, Moran's I, LISA, SLM |
| 29.1.4 | `pipeline/04_visualize.jl` | 4-panel atlas, K-function |
| 30 | `notebooks/healthcare_dashboard.jl` | Pluto.jl reactive dashboard |
| 31.1 | `web/app.jl` | Genie.jl REST API |
| 31.2 | `web/Dockerfile` | Docker containerization |
| 33 | `scripts/gpu_acceleration.jl` | CUDA/Metal acceleration |
| 34.1 | `specs/BUILD_EVERYTHING.md` | Master build program |
| 34.2 | `test/integration_test.jl` | Integration tests |

---

## API Endpoints Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | Health check + county count |
| GET | `/api/counties` | All 53 county summaries |
| GET | `/api/county/:geoid` | Single county detail + neighbors |
| POST | `/api/moran` | Moran's I for custom variable array |
| GET | `/api/access?catchment=N` | Recompute E2SFCA access (1–200 km) |
| GET | `/api/lisa?alpha=N` | LISA cluster map (α = 0.001–0.20) |

---

## Registry Submission Checklist (PointPatterns.jl)

- [ ] `Project.toml`: name, uuid, version=0.1.0, julia ≥ 1.10
- [ ] `src/PointPatterns.jl`: module with `export` block
- [ ] `test/runtests.jl`: all 16 testsets passing
- [ ] `README.md`: installation, quick-start, API reference
- [ ] `LICENSE`: MIT
- [ ] Tag v0.1.0 and open PR on JuliaRegistries/General
- [ ] CI: `.github/workflows/test.yml` (Julia 1.10 + 1.11 matrix)

---

*Vol 4 — Open-Source Healthcare GIS Textbook in Julia*
*Chapters 26–34 | Timothy Hartzog*
