"""
Pipeline templates and common workflows.
"""

function create_weather_analysis_pipeline()
    @info "Creating weather analysis pipeline"
    pipeline = WorkflowPipeline("WeatherAnalysis")
    add_step(pipeline, "fetch_weather", (x) -> x)
    add_step(pipeline, "validate_data", (x) -> x)
    add_step(pipeline, "analyze_trends", (x) -> x)
    return pipeline
end

function create_disaster_risk_pipeline()
    @info "Creating disaster risk assessment pipeline"
    pipeline = WorkflowPipeline("DisasterRisk")
    add_step(pipeline, "ingest_hazard_data", (x) -> x)
    add_step(pipeline, "assess_exposure", (x) -> x)
    add_step(pipeline, "calculate_risk", (x) -> x)
    return pipeline
end

function create_environmental_monitoring_pipeline()
    @info "Creating environmental monitoring pipeline"
    pipeline = WorkflowPipeline("EnvironmentalMonitoring")
    add_step(pipeline, "fetch_sensor_data", (x) -> x)
    add_step(pipeline, "aggregate_measurements", (x) -> x)
    add_step(pipeline, "detect_anomalies", (x) -> x)
    return pipeline
end

function create_urban_planning_pipeline()
    @info "Creating urban planning pipeline"
    pipeline = WorkflowPipeline("UrbanPlanning")
    add_step(pipeline, "fetch_osm_data", (x) -> x)
    add_step(pipeline, "analyze_land_use", (x) -> x)
    add_step(pipeline, "generate_recommendations", (x) -> x)
    return pipeline
end
