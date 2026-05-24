# Geo-Julia Gap Analysis Dashboard

Interactive Genie/Stipple web dashboard for visualizing the SciML gap analysis.

## Quick Start

```bash
cd gap_analysis_app
chmod +x run.sh
./run.sh
```

Or manually:

```bash
cd gap_analysis_app
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. src/app.jl
```

Open http://localhost:8080 in your browser.

## Features

- **Overview Tab**: Severity distribution, ecosystem adoption gauge, LOC by volume, domain breakdown
- **Gap Details Tab**: Searchable table of all 35 identified gaps with severity, LOC, and recommended replacements
- **Volume Analysis Tab**: Per-volume breakdown showing which volumes use ecosystem packages vs custom code
- **SciML Packages Tab**: Catalog of 17 recommended replacement packages with maturity and ecosystem info
- **Migration Plan Tab**: 4-phase, 12-week migration roadmap with task breakdown

## API Endpoints

- `GET /api/gaps` — All gap items as JSON
- `GET /api/summary` — Summary statistics
- `GET /api/packages` — Recommended SciML packages
- `GET /api/migration` — Migration phases

## Environment Variables

- `GAP_ANALYSIS_PORT` — Server port (default: 8080)

## Stack

- **Genie.jl** — Julia web framework (routing, HTTP server)
- **Stipple.jl** — Reactive UI framework for Julia
- **StippleUI** — Quasar-based UI components
- **StipplePlotly** — Interactive Plotly charts
