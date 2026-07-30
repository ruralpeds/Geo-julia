# GeoSpatial Analysis Engine - Docker Image
# Production-ready containerized deployment

# Build stage
FROM julia:1.9 as builder

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    libgeos-dev \
    libproj-dev \
    gdal-bin \
    && rm -rf /var/lib/apt/lists/*

# Copy project files
COPY GeoSpatialEngine/ /app/

# Install Julia dependencies
RUN julia --project=/app -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

# Runtime stage
FROM julia:1.9

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libgeos-c1v5 \
    libproj-dev \
    gdal-bin \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy built dependencies from builder
COPY --from=builder /app /app
COPY --from=builder /root/.julia /root/.julia

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Default environment variables
ENV HOST=0.0.0.0 \
    PORT=8080 \
    JULIA_NUM_THREADS=4 \
    JULIA_OPTIMIZE=2

# Expose API port
EXPOSE 8080

# Start API server
CMD ["julia", "--project=/app", "-e", "using GeoSpatialEngine; engine = GeoSpatialAnalysisEngine(); server = create_api_server(engine; host=\"${HOST}\", port=${PORT}); start_api_server(server)"]
