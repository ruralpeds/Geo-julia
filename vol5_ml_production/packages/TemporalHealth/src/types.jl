# types.jl — Core data structures for health time series
# Chapter 37.1

"""
    HealthTimeSeries

Regular or irregular time series of a health metric.

Fields:
- `times`    — Vector of Dates or numeric time indices
- `values`   — Observed values (n,)
- `name`     — Variable name (e.g., "access_score", "mortality_rate")
- `unit`     — Unit string (e.g., "per 100k", "ratio")
- `freq`     — Observations per year (12=monthly, 4=quarterly, 1=annual, 0=irregular)
- `metadata` — Optional DataFrame with additional covariates (n rows)
"""
struct HealthTimeSeries{T <: Union{Date, Real}}
    times   ::Vector{T}
    values  ::Vector{Float64}
    name    ::String
    unit    ::String
    freq    ::Int
    metadata::Union{DataFrame, Nothing}
end

"""
    from_dataframe(df, time_col, value_col; name, unit, freq) -> HealthTimeSeries
"""
function from_dataframe(df        ::DataFrame,
                        time_col  ::Symbol,
                        value_col ::Symbol;
                        name ::String = String(value_col),
                        unit ::String = "",
                        freq ::Int    = 1,
                        meta_cols::Vector{Symbol} = Symbol[])
    times  = df[!, time_col]
    vals   = Float64.(df[!, value_col])
    meta   = isempty(meta_cols) ? nothing : df[!, meta_cols]
    HealthTimeSeries(times, vals, name, unit, freq, meta)
end

Base.length(ts::HealthTimeSeries) = length(ts.values)
Base.show(io::IO, ts::HealthTimeSeries) =
    print(io, "HealthTimeSeries($(ts.name), n=$(length(ts)), freq=$(ts.freq))")
