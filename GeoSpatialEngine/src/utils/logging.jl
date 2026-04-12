"""
Logging and monitoring utilities.
"""

function setup_logging(level::String=get(ENV, "GEO_LOG_LEVEL", "Info"))
    global_logger(ConsoleLogger(stderr, Symbol(level)))
    @info "Logging initialized at level: $level"
end

function log_analysis_event(event::String, metadata::Dict=Dict())
    @info "Analysis Event: $event" metadata...
end

function create_performance_monitor()
    @info "Creating performance monitor"
    return Dict("start_time" => now(UTC), "events" => [])
end

function log_performance_metric(monitor::Dict, metric_name::String, value::Float64)
    push!(monitor["events"], (metric=metric_name, value=value, time=now(UTC)))
end
