"""
REST API Server Tests

Tests for:
- API server initialization
- Request/response handling
- All API endpoints
- Authentication
- Rate limiting
- Job management
- Error handling
"""

using Test
using HTTP
using JSON3
using GeoSpatialEngine
using Dates

@testset "REST API Server" begin

    # Create API server for testing
    engine = GeoSpatialAnalysisEngine()
    server = create_api_server(engine; host="127.0.0.1", port=8888)

    # ========================================================================
    # Initialization Tests
    # ========================================================================

    @testset "Server Initialization" begin

        @test begin
            server isa APIServer
        end

        @test begin
            server.host == "127.0.0.1"
        end

        @test begin
            server.port == 8888
        end

        @test begin
            isa(server.jobs, Dict)
        end

        @test begin
            isa(server.auth_tokens, Dict) && !isempty(server.auth_tokens)
        end

        @test begin
            isa(server.job_lock, ReentrantLock)
        end
    end

    # ========================================================================
    # Request/Response Structure Tests
    # ========================================================================

    @testset "Request/Response Structures" begin

        @test begin
            req = APIRequest(
                "test-id",
                "POST",
                "/analyze",
                Dict("Content-Type" => "application/json"),
                "{\"operation\": \"buffer\"}",
                now(),
                "user1"
            )
            req isa APIRequest && req.id == "test-id"
        end

        @test begin
            resp = APIResponse(
                200,
                Dict("status" => "ok"),
                "Success",
                now()
            )
            resp.status == 200
        end

        @test begin
            job = AnalysisJob(
                "job-1",
                "pending",
                "buffer",
                Dict("distance" => 100),
                nothing,
                nothing,
                now(),
                nothing,
                nothing,
                0.0
            )
            job.status == "pending"
        end
    end

    # ========================================================================
    # Health/Status Endpoints
    # ========================================================================

    @testset "Health & Status Endpoints" begin

        @test begin
            req = APIRequest(
                string(uuid4()),
                "GET",
                "/health",
                Dict(),
                nothing,
                now(),
                nothing
            )
            resp = handle_health(server, req)
            resp.status == 200 && resp.data["status"] == "healthy"
        end

        @test begin
            req = APIRequest(
                string(uuid4()),
                "GET",
                "/status",
                Dict(),
                nothing,
                now(),
                nothing
            )
            resp = handle_status(server, req)
            resp.status == 200 && haskey(resp.data, "active_jobs")
        end
    end

    # ========================================================================
    # Data Ingestion Endpoint
    # ========================================================================

    @testset "Data Ingestion" begin

        @test begin
            req_body = JSON3.write(Dict(
                "source" => "NOAA",
                "format" => "JSON",
                "data" => Dict(
                    "latitude" => [40.7, 40.8],
                    "longitude" => [-74.0, -74.1]
                )
            ))

            req = APIRequest(
                string(uuid4()),
                "POST",
                "/ingest",
                Dict(),
                req_body,
                now(),
                nothing
            )
            resp = handle_ingest(server, req)
            resp.status == 200 && resp.data["source"] == "NOAA"
        end

        @test begin
            # Missing source
            req_body = JSON3.write(Dict(
                "format" => "JSON",
                "data" => Dict()
            ))

            req = APIRequest(
                string(uuid4()),
                "POST",
                "/ingest",
                Dict(),
                req_body,
                now(),
                nothing
            )
            resp = handle_ingest(server, req)
            resp.status == 400
        end
    end

    # ========================================================================
    # Analysis Endpoints
    # ========================================================================

    @testset "Synchronous Analysis" begin

        @test begin
            req_body = JSON3.write(Dict(
                "operation" => "buffer",
                "params" => Dict("distance" => 100)
            ))

            req = APIRequest(
                string(uuid4()),
                "POST",
                "/analyze",
                Dict(),
                req_body,
                now(),
                nothing
            )
            resp = handle_analyze(server, req)
            resp.status == 200 && resp.data["status"] == "completed"
        end

        @test begin
            # Missing operation
            req_body = JSON3.write(Dict(
                "params" => Dict()
            ))

            req = APIRequest(
                string(uuid4()),
                "POST",
                "/analyze",
                Dict(),
                req_body,
                now(),
                nothing
            )
            resp = handle_analyze(server, req)
            resp.status == 400
        end
    end

    # ========================================================================
    # Asynchronous Job Submission
    # ========================================================================

    @testset "Async Job Submission" begin

        @test begin
            req_body = JSON3.write(Dict(
                "operation" => "hotspot_analysis",
                "params" => Dict("variable" => "temperature")
            ))

            req = APIRequest(
                string(uuid4()),
                "POST",
                "/analyze/async",
                Dict(),
                req_body,
                now(),
                nothing
            )
            resp = handle_analyze_async(server, req)
            resp.status == 202 && haskey(resp.data, "job_id")
        end

        @test begin
            # Missing operation
            req_body = JSON3.write(Dict(
                "params" => Dict()
            ))

            req = APIRequest(
                string(uuid4()),
                "POST",
                "/analyze/async",
                Dict(),
                req_body,
                now(),
                nothing
            )
            resp = handle_analyze_async(server, req)
            resp.status == 400
        end
    end

    # ========================================================================
    # Job Status Retrieval
    # ========================================================================

    @testset "Job Management" begin

        # Submit a job first
        req_body = JSON3.write(Dict(
            "operation" => "cluster_analysis",
            "params" => Dict("n_clusters" => 5)
        ))

        req = APIRequest(
            string(uuid4()),
            "POST",
            "/analyze/async",
            Dict(),
            req_body,
            now(),
            nothing
        )
        resp = handle_analyze_async(server, req)
        job_id = resp.data["job_id"]

        @test begin
            # Retrieve job status
            status_req = APIRequest(
                string(uuid4()),
                "GET",
                "/jobs/$job_id",
                Dict(),
                nothing,
                now(),
                nothing
            )
            status_resp = handle_job(server, status_req, job_id)
            status_resp.status == 200 && status_resp.data["status"] == "pending"
        end

        @test begin
            # Non-existent job
            bad_req = APIRequest(
                string(uuid4()),
                "GET",
                "/jobs/nonexistent",
                Dict(),
                nothing,
                now(),
                nothing
            )
            bad_resp = handle_job(server, bad_req, "nonexistent")
            bad_resp.status == 404
        end
    end

    # ========================================================================
    # ML Prediction Endpoint
    # ========================================================================

    @testset "ML Prediction" begin

        @test begin
            req_body = JSON3.write(Dict(
                "model_id" => "model-1",
                "features" => [[40.7, -74.0, 20.5], [40.8, -74.1, 21.3]]
            ))

            req = APIRequest(
                string(uuid4()),
                "POST",
                "/predict",
                Dict(),
                req_body,
                now(),
                nothing
            )
            resp = handle_predict(server, req)
            resp.status == 200 && haskey(resp.data, "predictions")
        end

        @test begin
            # Missing model_id
            req_body = JSON3.write(Dict(
                "features" => []
            ))

            req = APIRequest(
                string(uuid4()),
                "POST",
                "/predict",
                Dict(),
                req_body,
                now(),
                nothing
            )
            resp = handle_predict(server, req)
            resp.status == 400
        end
    end

    # ========================================================================
    # Visualization Endpoint
    # ========================================================================

    @testset "Visualization Generation" begin

        @test begin
            req_body = JSON3.write(Dict(
                "type" => "heatmap",
                "data" => Dict("variable" => "temperature")
            ))

            req = APIRequest(
                string(uuid4()),
                "POST",
                "/visualize",
                Dict(),
                req_body,
                now(),
                nothing
            )
            resp = handle_visualize(server, req)
            resp.status == 200 && haskey(resp.data, "url")
        end

        @test begin
            # Missing type
            req_body = JSON3.write(Dict(
                "data" => Dict()
            ))

            req = APIRequest(
                string(uuid4()),
                "POST",
                "/visualize",
                Dict(),
                req_body,
                now(),
                nothing
            )
            resp = handle_visualize(server, req)
            resp.status == 400
        end
    end

    # ========================================================================
    # Data Export Endpoint
    # ========================================================================

    @testset "Data Export" begin

        @test begin
            req_body = JSON3.write(Dict(
                "format" => "geojson",
                "data" => Dict("features" => [])
            ))

            req = APIRequest(
                string(uuid4()),
                "POST",
                "/export",
                Dict(),
                req_body,
                now(),
                nothing
            )
            resp = handle_export(server, req)
            resp.status == 200 && resp.data["format"] == "geojson"
        end

        @test begin
            req_body = JSON3.write(Dict(
                "format" => "geotiff",
                "data" => Dict()
            ))

            req = APIRequest(
                string(uuid4()),
                "POST",
                "/export",
                Dict(),
                req_body,
                now(),
                nothing
            )
            resp = handle_export(server, req)
            resp.status == 200 && resp.data["format"] == "geotiff"
        end
    end

    # ========================================================================
    # Authentication Endpoint
    # ========================================================================

    @testset "Authentication" begin

        @test begin
            req_body = JSON3.write(Dict(
                "username" => "admin",
                "password" => "changeme"
            ))

            req = APIRequest(
                string(uuid4()),
                "POST",
                "/auth/login",
                Dict(),
                req_body,
                now(),
                nothing
            )
            resp = handle_login(server, req)
            resp.status == 200 && haskey(resp.data, "token")
        end

        @test begin
            # Invalid credentials
            req_body = JSON3.write(Dict(
                "username" => "admin",
                "password" => "wrong"
            ))

            req = APIRequest(
                string(uuid4()),
                "POST",
                "/auth/login",
                Dict(),
                req_body,
                now(),
                nothing
            )
            resp = handle_login(server, req)
            resp.status == 401
        end

        @test begin
            # Missing credentials
            req_body = JSON3.write(Dict(
                "username" => "admin"
            ))

            req = APIRequest(
                string(uuid4()),
                "POST",
                "/auth/login",
                Dict(),
                req_body,
                now(),
                nothing
            )
            resp = handle_login(server, req)
            resp.status == 401
        end
    end

    # ========================================================================
    # Rate Limiting
    # ========================================================================

    @testset "Rate Limiting" begin

        @test begin
            # First request should pass
            result1 = check_rate_limit(server, "user1"; max_requests=3, window_seconds=60)
            result1 == true
        end

        @test begin
            # Fill up limit
            check_rate_limit(server, "user2"; max_requests=2, window_seconds=60)
            result = check_rate_limit(server, "user2"; max_requests=2, window_seconds=60)
            result == true  # Still within limit
        end

        @test begin
            # Exceed limit
            user = "user3"
            check_rate_limit(server, user; max_requests=1, window_seconds=60)
            check_rate_limit(server, user; max_requests=1, window_seconds=60)
            result = check_rate_limit(server, user; max_requests=1, window_seconds=60)
            result == false  # Rate limited
        end
    end

    # ========================================================================
    # Response Helper Tests
    # ========================================================================

    @testset "Response Helpers" begin

        @test begin
            resp = GeoSpatialEngine.api_response(200, Dict("ok" => true), "Success")
            resp.status == 200 && resp.message == "Success"
        end

        @test begin
            resp = GeoSpatialEngine.api_response(400, Dict(), "Error message")
            resp.status == 400
        end

        @test begin
            resp = GeoSpatialEngine.api_response(500, "Error", "Server error")
            resp.status == 500
        end
    end

    # ========================================================================
    # Integration Tests
    # ========================================================================

    @testset "Complete API Workflows" begin

        @test begin
            # Full ingest → analyze → predict workflow
            # 1. Ingest
            ingest_req = APIRequest(
                string(uuid4()),
                "POST",
                "/ingest",
                Dict(),
                JSON3.write(Dict(
                    "source" => "NOAA",
                    "data" => Dict(
                        "latitude" => [40.7, 40.8, 40.9],
                        "longitude" => [-74.0, -74.1, -74.2],
                        "temperature" => [20.5, 21.0, 20.8]
                    )
                )),
                now(),
                nothing
            )
            ingest_resp = handle_ingest(server, ingest_req)

            # 2. Analyze
            analysis_req = APIRequest(
                string(uuid4()),
                "POST",
                "/analyze",
                Dict(),
                JSON3.write(Dict(
                    "operation" => "hotspot_analysis",
                    "params" => Dict("variable" => "temperature")
                )),
                now(),
                nothing
            )
            analysis_resp = handle_analyze(server, analysis_req)

            # 3. Predict
            predict_req = APIRequest(
                string(uuid4()),
                "POST",
                "/predict",
                Dict(),
                JSON3.write(Dict(
                    "model_id" => "hotspot_model",
                    "features" => [[40.7, -74.0]]
                )),
                now(),
                nothing
            )
            predict_resp = handle_predict(server, predict_req)

            ingest_resp.status == 200 && analysis_resp.status == 200 && predict_resp.status == 200
        end

        @test begin
            # Async analysis workflow
            # 1. Submit async job
            job_req = APIRequest(
                string(uuid4()),
                "POST",
                "/analyze/async",
                Dict(),
                JSON3.write(Dict(
                    "operation" => "kriging",
                    "params" => Dict("variable" => "temperature")
                )),
                now(),
                nothing
            )
            job_resp = handle_analyze_async(server, job_req)
            job_id = job_resp.data["job_id"]

            # 2. Check status
            status_req = APIRequest(
                string(uuid4()),
                "GET",
                "/jobs/$job_id",
                Dict(),
                nothing,
                now(),
                nothing
            )
            status_resp = handle_job(server, status_req, job_id)

            # 3. Export results
            export_req = APIRequest(
                string(uuid4()),
                "POST",
                "/export",
                Dict(),
                JSON3.write(Dict(
                    "format" => "geojson",
                    "data" => Dict()
                )),
                now(),
                nothing
            )
            export_resp = handle_export(server, export_req)

            job_resp.status == 202 && status_resp.status == 200 && export_resp.status == 200
        end

        @test begin
            # Visualization workflow
            # 1. Ingest
            ingest_req = APIRequest(
                string(uuid4()),
                "POST",
                "/ingest",
                Dict(),
                JSON3.write(Dict(
                    "source" => "OSM",
                    "data" => Dict(
                        "latitude" => [40.7],
                        "longitude" => [-74.0]
                    )
                )),
                now(),
                nothing
            )
            ingest_resp = handle_ingest(server, ingest_req)

            # 2. Visualize
            viz_req = APIRequest(
                string(uuid4()),
                "POST",
                "/visualize",
                Dict(),
                JSON3.write(Dict(
                    "type" => "map",
                    "data" => Dict()
                )),
                now(),
                nothing
            )
            viz_resp = handle_visualize(server, viz_req)

            ingest_resp.status == 200 && viz_resp.status == 200
        end
    end

end

println("\n✅ All REST API tests passed!")
