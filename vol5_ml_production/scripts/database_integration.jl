#!/usr/bin/env julia
# scripts/database_integration.jl
# PostgreSQL + PostGIS integration for production healthcare GIS
# Chapter 39 — Julia Healthcare GIS Textbook, Vol 5
#
# Requirements:
#   - PostgreSQL 14+ with PostGIS 3+ extension
#   - ENV["POSTGRES_URL"] = "postgresql://user:pass@localhost:5432/healthcare_geo"
#   - Julia packages: LibPQ.jl (optional, graceful fallback to in-memory)

using DataFrames, Statistics

# ── Connection management ──────────────────────────────────────────────────────

const LIBPQ_AVAILABLE = try
    @eval using LibPQ
    true
catch
    false
end

"""
    HealthGeoConnection

Wrapper around a PostgreSQL connection with healthcare GIS utilities.
"""
struct HealthGeoConnection
    conn   ::Any   # LibPQ.Connection or Nothing
    url    ::String
    active ::Bool
end

"""
    connect(; url=ENV["POSTGRES_URL"]) -> HealthGeoConnection

Connect to PostgreSQL with PostGIS. Falls back to in-memory mode if unavailable.
"""
function connect(; url::String = get(ENV, "POSTGRES_URL", ""))
    !LIBPQ_AVAILABLE && (@warn "LibPQ.jl not available; using in-memory fallback";
                         return HealthGeoConnection(nothing, url, false))
    isempty(url) && (@warn "POSTGRES_URL not set; using in-memory fallback";
                     return HealthGeoConnection(nothing, url, false))
    try
        conn = LibPQ.Connection(url)
        @info "Connected to PostgreSQL at $(url)"
        HealthGeoConnection(conn, url, true)
    catch e
        @warn "PostgreSQL connection failed: $e; using in-memory fallback"
        HealthGeoConnection(nothing, url, false)
    end
end

"""
    close!(hgc::HealthGeoConnection)
"""
function close!(hgc::HealthGeoConnection)
    hgc.active && !isnothing(hgc.conn) && LibPQ.close(hgc.conn)
end

# ── Schema initialisation ──────────────────────────────────────────────────────

const SCHEMA_SQL = """
-- Enable PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;

-- Counties table with geometry
CREATE TABLE IF NOT EXISTS counties (
    geoid        VARCHAR(5)     PRIMARY KEY,
    name         VARCHAR(100)   NOT NULL,
    state_fips   VARCHAR(2)     NOT NULL,
    geom         GEOMETRY(MULTIPOLYGON, 4326),
    area_km2     DOUBLE PRECISION,
    centroid_lat DOUBLE PRECISION,
    centroid_lon DOUBLE PRECISION
);

-- Demographics (ACS)
CREATE TABLE IF NOT EXISTS demographics (
    geoid        VARCHAR(5)     REFERENCES counties(geoid),
    year         INTEGER        NOT NULL,
    total_pop    INTEGER,
    poverty_pct  DOUBLE PRECISION,
    uninsured_pct DOUBLE PRECISION,
    median_income DOUBLE PRECISION,
    PRIMARY KEY (geoid, year)
);

-- Healthcare providers
CREATE TABLE IF NOT EXISTS providers (
    npi          VARCHAR(10)    PRIMARY KEY,
    name         VARCHAR(200),
    provider_type VARCHAR(50),
    lat          DOUBLE PRECISION,
    lon          DOUBLE PRECISION,
    geom         GEOMETRY(POINT, 4326),
    county_geoid  VARCHAR(5)    REFERENCES counties(geoid),
    fte          DOUBLE PRECISION DEFAULT 1.0
);
CREATE INDEX IF NOT EXISTS idx_providers_geom ON providers USING GIST(geom);

-- Access scores (computed results)
CREATE TABLE IF NOT EXISTS access_scores (
    geoid          VARCHAR(5)     REFERENCES counties(geoid),
    computed_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    catchment_km   DOUBLE PRECISION,
    access_score   DOUBLE PRECISION,
    moran_i        DOUBLE PRECISION,
    lisa_cluster   VARCHAR(2),
    PRIMARY KEY (geoid, computed_at, catchment_km)
);

-- Materialized view for fast dashboard queries
CREATE MATERIALIZED VIEW IF NOT EXISTS county_access_latest AS
    SELECT c.geoid, c.name, c.centroid_lat, c.centroid_lon,
           d.total_pop, d.poverty_pct, d.uninsured_pct,
           a.access_score, a.moran_i, a.lisa_cluster,
           a.catchment_km, a.computed_at
    FROM counties c
    LEFT JOIN demographics d USING (geoid)
    LEFT JOIN (
        SELECT DISTINCT ON (geoid) *
        FROM access_scores
        ORDER BY geoid, computed_at DESC
    ) a USING (geoid)
    WHERE d.year = (SELECT MAX(year) FROM demographics);

CREATE UNIQUE INDEX IF NOT EXISTS idx_cal_geoid ON county_access_latest(geoid);
"""

"""
    init_schema!(hgc::HealthGeoConnection)

Create tables, indexes, and materialised view if they don't exist.
"""
function init_schema!(hgc::HealthGeoConnection)
    !hgc.active && (@info "In-memory mode: schema init skipped"; return)
    LibPQ.execute(hgc.conn, SCHEMA_SQL)
    @info "Schema initialised"
end

# ── Spatial SQL queries ────────────────────────────────────────────────────────

"""
    query_counties_within_km(hgc, lat, lon, radius_km) -> DataFrame

PostGIS query: counties whose centroid is within `radius_km` of (lat, lon).

SQL uses ST_DWithin with geography type for accurate km distance.
"""
function query_counties_within_km(hgc       ::HealthGeoConnection,
                                   lat       ::Float64,
                                   lon       ::Float64,
                                   radius_km ::Float64)::DataFrame
    !hgc.active && return _synthetic_counties_df(20)

    sql = """
    SELECT c.geoid, c.name,
           ST_Distance(
               c.geom::geography,
               ST_SetSRID(ST_MakePoint(\$1, \$2), 4326)::geography
           ) / 1000.0 AS dist_km,
           d.total_pop, d.poverty_pct, d.uninsured_pct
    FROM counties c
    JOIN demographics d USING (geoid)
    WHERE d.year = (SELECT MAX(year) FROM demographics)
      AND ST_DWithin(
              c.geom::geography,
              ST_SetSRID(ST_MakePoint(\$1, \$2), 4326)::geography,
              \$3 * 1000
          )
    ORDER BY dist_km;
    """
    result = LibPQ.execute(hgc.conn, sql, [lon, lat, radius_km])
    DataFrame(result)
end

"""
    query_provider_catchments(hgc; catchment_km=50.0) -> DataFrame

For each county, count providers within catchment and compute E2SFCA ratio.
"""
function query_provider_catchments(hgc       ::HealthGeoConnection;
                                    catchment_km::Float64 = 50.0)::DataFrame
    !hgc.active && return _synthetic_access_df()

    sql = """
    WITH prov_county AS (
        SELECT c.geoid,
               SUM(p.fte * EXP(
                   -ST_Distance(c.geom::geography, p.geom::geography)^2
                   / (2.0 * (\$1 * 1000.0 / 3.0)^2)
               )) AS weighted_providers,
               COUNT(p.npi) AS n_providers
        FROM counties c
        CROSS JOIN providers p
        WHERE ST_DWithin(c.geom::geography, p.geom::geography, \$1 * 1000)
        GROUP BY c.geoid
    )
    SELECT c.geoid, c.name, c.centroid_lat, c.centroid_lon,
           d.total_pop, d.poverty_pct, d.uninsured_pct,
           COALESCE(pc.weighted_providers, 0) AS weighted_providers,
           COALESCE(pc.n_providers, 0) AS n_providers,
           COALESCE(pc.weighted_providers / NULLIF(d.total_pop, 0), 0) AS access_score
    FROM counties c
    JOIN demographics d USING (geoid)
    LEFT JOIN prov_county pc USING (geoid)
    WHERE d.year = (SELECT MAX(year) FROM demographics)
    ORDER BY c.geoid;
    """
    result = LibPQ.execute(hgc.conn, sql, [catchment_km])
    DataFrame(result)
end

"""
    upsert_access_scores!(hgc, df; catchment_km) -> Int

Insert computed access scores. Returns number of rows upserted.
"""
function upsert_access_scores!(hgc       ::HealthGeoConnection,
                                df        ::DataFrame;
                                catchment_km::Float64 = 50.0)::Int
    !hgc.active && (@info "In-memory mode: upsert skipped"; return 0)

    n = 0
    for row in eachrow(df)
        LibPQ.execute(hgc.conn, """
        INSERT INTO access_scores (geoid, catchment_km, access_score, moran_i, lisa_cluster)
        VALUES (\$1, \$2, \$3, \$4, \$5)
        ON CONFLICT (geoid, computed_at, catchment_km) DO UPDATE
          SET access_score = EXCLUDED.access_score,
              moran_i = EXCLUDED.moran_i,
              lisa_cluster = EXCLUDED.lisa_cluster;
        """, [row.geoid, catchment_km,
              get(row, :access_score, missing),
              get(row, :moran_i, missing),
              get(row, :lisa_cluster, missing)])
        n += 1
    end
    LibPQ.execute(hgc.conn, "REFRESH MATERIALIZED VIEW CONCURRENTLY county_access_latest;")
    @info "Upserted $n rows; materialised view refreshed"
    n
end

"""
    query_spatial_neighbors(hgc, geoid) -> Vector{String}

Return GEOIDs of counties sharing a border (queen contiguity) via PostGIS.
"""
function query_spatial_neighbors(hgc::HealthGeoConnection, geoid::String)::Vector{String}
    !hgc.active && return String[]
    result = LibPQ.execute(hgc.conn, """
    SELECT b.geoid FROM counties a
    JOIN counties b ON a.geoid != b.geoid
      AND ST_Touches(a.geom, b.geom)
    WHERE a.geoid = \$1;
    """, [geoid])
    [row.geoid for row in result]
end

# ── Synthetic fallback ─────────────────────────────────────────────────────────

function _synthetic_counties_df(n)
    DataFrame(
        geoid       = ["38" * lpad(i,3,'0') for i in 1:n],
        name        = ["County $i" for i in 1:n],
        dist_km     = sort(rand(n) .* 100),
        total_pop   = rand(500:20000, n),
        poverty_pct = 5.0 .+ rand(n) .* 20,
        uninsured_pct = 8.0 .+ rand(n) .* 15,
    )
end

function _synthetic_access_df()
    n = 53
    DataFrame(
        geoid       = ["38" * lpad(i,3,'0') for i in 1:n],
        name        = ["County $i" for i in 1:n],
        centroid_lat = 46.5 .+ randn(n),
        centroid_lon = -100.5 .+ randn(n) .* 2,
        total_pop    = rand(500:50000, n),
        poverty_pct  = 5.0 .+ rand(n) .* 20,
        uninsured_pct = 8.0 .+ rand(n) .* 15,
        access_score  = abs.(randn(n)) .* 0.01 .+ 0.003,
        n_providers   = rand(0:15, n),
    )
end

# ── Demo ──────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__
    @info "Database Integration Demo — Chapter 39"
    @info "LibPQ.jl available: $LIBPQ_AVAILABLE"

    hgc = connect()
    @info "Connection active: $(hgc.active)"

    if !hgc.active
        @info "Running with synthetic fallback data"
        df = query_provider_catchments(hgc; catchment_km=50.0)
        @info "Got $(nrow(df)) county records"
        @info "Mean access score: $(round(mean(df.access_score); digits=4))"
        @info "Columns: $(names(df))"
    end

    @info "Chapter 39 demo complete"
end
