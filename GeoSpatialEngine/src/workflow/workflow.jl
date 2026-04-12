"""
Workflow orchestration for geospatial analysis pipelines.
"""

function create_analysis_pipeline(name::String)
    @info "Creating analysis pipeline: $name"
    return WorkflowPipeline(name)
end

function add_step(pipeline::WorkflowPipeline, step_name::String, step_fn::Function)
    @info "Adding step '$step_name' to pipeline '$(pipeline.name)'"
    push!(pipeline.steps, (name=step_name, fn=step_fn))
    return pipeline
end

function execute_pipeline(pipeline::WorkflowPipeline; inputs::Dict=Dict())
    @info "Executing pipeline: $(pipeline.name)"

    current_data = inputs

    for (i, step) in enumerate(pipeline.steps)
        @info "Executing step $(i): $(step.name)"
        current_data = step.fn(current_data)
        pipeline.data_store[step.name] = current_data
    end

    @info "Pipeline execution completed"
    return current_data
end

function get_pipeline_results(pipeline::WorkflowPipeline)
    return pipeline.data_store
end

function save_pipeline(pipeline::WorkflowPipeline, filepath::String)
    @info "Saving pipeline to: $filepath"
end

function load_pipeline(filepath::String)
    @info "Loading pipeline from: $filepath"
    return WorkflowPipeline("loaded")
end
