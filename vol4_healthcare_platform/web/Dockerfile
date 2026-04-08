# === Dockerfile for HealthcareGIS Genie.jl Web Service ===
# Vol 4 — Chapter 31.2: Containerized Deployment
#
# Build:  docker build -t healthcare-geo:latest .
# Run:    docker run -p 8080:8080 --env CENSUS_API_KEY=$CENSUS_API_KEY \
#                   healthcare-geo:latest
# Test:   curl http://localhost:8080/api/health | jq
#         curl http://localhost:8080/api/counties | jq '.[0]'
#         curl 'http://localhost:8080/api/access?catchment=30' | jq 'length'

FROM julia:1.10-bullseye

WORKDIR /app

# ── Install system dependencies for GDAL, PROJ, GEOS ─────────────────────────
# Required by ArchGDAL.jl and GeoInterface.jl
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgdal-dev \
    libproj-dev \
    libgeos-dev \
    && rm -rf /var/lib/apt/lists/*

# ── Copy project files ────────────────────────────────────────────────────────
COPY Project.toml Manifest.toml* ./
COPY packages/ ./packages/
COPY web/ ./web/
COPY scripts/ ./scripts/

# Create data directories
RUN mkdir -p data/processed data/raw

# Copy any pre-computed analysis results (if available)
# In production, mount as a volume instead:
# docker run -v /path/to/data:/app/data healthcare-geo:latest
# COPY data/processed/ ./data/processed/

# ── Pre-compile all packages ──────────────────────────────────────────────────
# This bakes the package compilation into the Docker layer for fast container startup
RUN julia --project=. -e 'import Pkg; Pkg.instantiate()' \
    && julia --project=. -e 'import Pkg; Pkg.precompile()'

# ── Create PackageCompiler sysimage for fast startup ─────────────────────────
# Reduces startup latency from ~30s to ~3s
RUN julia --project=. -e '
using PackageCompiler
create_sysimage(
    [:Genie, :DataFrames, :CSV, :JSON3, :SparseArrays, :Statistics, :NearestNeighbors],
    sysimage_path="/app/geo_sysimage.so",
    precompile_statements_file=nothing
)
' || echo "PackageCompiler sysimage creation failed — using standard startup"

# ── Health check ──────────────────────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/api/health || exit 1

EXPOSE 8080

# ── Environment variables ─────────────────────────────────────────────────────
ENV CENSUS_API_KEY=""
ENV JULIA_NUM_THREADS="auto"
ENV GENIE_ENV="production"

# ── Start server ──────────────────────────────────────────────────────────────
# Use sysimage if available, otherwise standard Julia
CMD if [ -f /app/geo_sysimage.so ]; then \
        julia -J/app/geo_sysimage.so --project=. web/app.jl; \
    else \
        julia --project=. web/app.jl; \
    fi
