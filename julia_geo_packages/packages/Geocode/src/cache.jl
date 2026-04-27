const CACHE_DIR = joinpath(homedir(), ".cache", "geocode")
const CACHE_DB = joinpath(CACHE_DIR, "cache.db")
const CACHE_TTL_DAYS = 180  # 6 months

# Thread-safe cache database connection
const _CACHE_LOCK = ReentrantLock()
const _DB_CONN = Ref{Union{SQLite.DB, Nothing}}(nothing)

"""
    initialize_cache() -> SQLite.DB

Initialize or open the geocoding cache database. Creates schema if needed.
"""
function initialize_cache()::SQLite.DB
    lock(_CACHE_LOCK) do
        if _DB_CONN[] !== nothing
            return _DB_CONN[]
        end

        # Create cache directory if it doesn't exist
        mkpath(CACHE_DIR)

        # Open database
        db = SQLite.DB(CACHE_DB)

        # Create cache table if it doesn't exist
        SQLite.execute(db, """
            CREATE TABLE IF NOT EXISTS geocode_cache (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                address_hash TEXT UNIQUE NOT NULL,
                original_address TEXT NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                match_quality INTEGER NOT NULL,
                source TEXT NOT NULL,
                matched_address TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                expires_at DATETIME NOT NULL
            )
        """)

        # Create indexes
        SQLite.execute(db, "CREATE INDEX IF NOT EXISTS idx_address_hash ON geocode_cache(address_hash)")
        SQLite.execute(db, "CREATE INDEX IF NOT EXISTS idx_expires_at ON geocode_cache(expires_at)")

        _DB_CONN[] = db
        return db
    end
end

"""
    clear_cache()

Remove all cached entries and close the database connection.
"""
function clear_cache()
    lock(_CACHE_LOCK) do
        if _DB_CONN[] !== nothing
            SQLite.close(_DB_CONN[])
            _DB_CONN[] = nothing
        end

        if isfile(CACHE_DB)
            rm(CACHE_DB)
        end
    end
end

"""
    get_cached_result(address::String) -> Union{GeocodeResult, Nothing}

Look up address in cache. Returns nothing if not found or expired.
"""
function get_cached_result(address::String)::Union{GeocodeResult, Nothing}
    hash = address_hash(address)

    lock(_CACHE_LOCK) do
        db = initialize_cache()

        # Query cache, filtering out expired entries
        query = """
            SELECT original_address, latitude, longitude, match_quality, source, matched_address
            FROM geocode_cache
            WHERE address_hash = ? AND expires_at > datetime('now')
            LIMIT 1
        """

        try
            result = SQLite.DBInterface.execute(db, query, [hash]) |> DataFrame

            if nrow(result) > 0
                row = result[1, :]
                quality = QualityLevel(Int(row.match_quality))
                return GeocodeResult(
                    row.original_address,
                    row.latitude,
                    row.longitude,
                    quality,
                    "cache",
                    row.matched_address
                )
            end
        catch e
            @warn "Error querying cache: $e"
        end

        return nothing
    end
end

"""
    cache_result(result::GeocodeResult)

Store a geocoding result in the cache.
"""
function cache_result(result::GeocodeResult)
    # Don't cache error results
    if result.error !== nothing
        return
    end

    # Don't cache unknown matches
    if result.match_quality == UNKNOWN
        return
    end

    hash = address_hash(result.address)
    expires_at = now(UTC) + Day(CACHE_TTL_DAYS)

    lock(_CACHE_LOCK) do
        db = initialize_cache()

        try
            SQLite.execute(db,
                """
                INSERT OR REPLACE INTO geocode_cache
                (address_hash, original_address, latitude, longitude, match_quality, source, matched_address, expires_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [hash, result.address, result.latitude, result.longitude,
                 Int(result.match_quality), result.source, result.matched_address, expires_at]
            )
        catch e
            @warn "Error caching result: $e"
        end
    end
end

"""
    cleanup_expired_cache()

Remove expired entries from the cache database.
"""
function cleanup_expired_cache()
    lock(_CACHE_LOCK) do
        db = initialize_cache()

        try
            SQLite.execute(db,
                "DELETE FROM geocode_cache WHERE expires_at <= datetime('now')"
            )
        catch e
            @warn "Error cleaning up cache: $e"
        end
    end
end

"""
    get_cache_stats() -> NamedTuple

Return cache statistics (total entries, expired entries, cache size).
"""
function get_cache_stats()
    lock(_CACHE_LOCK) do
        db = initialize_cache()

        try
            total = SQLite.DBInterface.execute(db,
                "SELECT COUNT(*) as count FROM geocode_cache") |> DataFrame
            total_count = total[1, :count]

            expired = SQLite.DBInterface.execute(db,
                "SELECT COUNT(*) as count FROM geocode_cache WHERE expires_at <= datetime('now')") |> DataFrame
            expired_count = expired[1, :count]

            active_count = total_count - expired_count

            return (total=total_count, active=active_count, expired=expired_count)
        catch e
            @warn "Error getting cache stats: $e"
            return (total=0, active=0, expired=0)
        end
    end
end
