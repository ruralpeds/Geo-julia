# GeoSpatial Analysis Engine - REST API Documentation

**Version**: 1.0.0  
**Base URL**: `http://localhost:8080`  
**Authentication**: Token-based (Bearer tokens)  
**Response Format**: JSON

---

## Table of Contents

1. [Authentication](#authentication)
2. [Rate Limiting](#rate-limiting)
3. [Endpoints](#endpoints)
4. [Error Handling](#error-handling)
5. [Examples](#examples)

---

## Authentication

### Obtaining a Token

**Endpoint**: `POST /auth/login`

**Request**:
```json
{
    "username": "admin",
    "password": "changeme"
}
```

**Response** (200 OK):
```json
{
    "status": 200,
    "data": {
        "token": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "username": "admin",
        "expires_at": "2026-04-19T12:34:56"
    },
    "message": "Authentication successful",
    "timestamp": "2026-04-12T12:34:56"
}
```

### Using the Token

Include the token in the `Authorization` header:

```bash
curl -H "Authorization: Bearer a1b2c3d4-e5f6-7890-abcd-ef1234567890" \
     http://localhost:8080/status
```

---

## Rate Limiting

**Default Limits**: 100 requests per 60 seconds per user

**Response Headers**:
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 2026-04-12T12:35:00
```

**Rate Limit Exceeded** (429):
```json
{
    "status": 429,
    "data": {},
    "message": "Rate limit exceeded. Try again later.",
    "timestamp": "2026-04-12T12:34:56"
}
```

---

## Endpoints

### Health & Status

#### 1. Health Check

**Endpoint**: `GET /health`

**Description**: Check if API server is running

**Response** (200 OK):
```json
{
    "status": 200,
    "data": {
        "status": "healthy",
        "timestamp": "2026-04-12T12:34:56",
        "uptime": "running"
    },
    "message": "Server is healthy",
    "timestamp": "2026-04-12T12:34:56"
}
```

#### 2. Server Status

**Endpoint**: `GET /status`

**Description**: Get server statistics and metrics

**Response** (200 OK):
```json
{
    "status": 200,
    "data": {
        "server_host": "127.0.0.1",
        "server_port": 8080,
        "active_jobs": 5,
        "total_requests": 1234,
        "timestamp": "2026-04-12T12:34:56"
    },
    "message": "Server status retrieved",
    "timestamp": "2026-04-12T12:34:56"
}
```

---

### Data Ingestion

#### 3. Ingest Data

**Endpoint**: `POST /ingest`

**Description**: Ingest data from various sources

**Request**:
```json
{
    "source": "NOAA",
    "format": "JSON",
    "data": {
        "latitude": [40.7128, 40.7580, 40.8566],
        "longitude": [-74.0060, -73.9855, -74.2090],
        "temperature": [20.5, 22.1, 18.9],
        "humidity": [65.0, 70.0, 55.0]
    }
}
```

**Response** (200 OK):
```json
{
    "status": 200,
    "data": {
        "source": "NOAA",
        "rows_ingested": 3,
        "columns": ["latitude", "longitude", "temperature", "humidity"]
    },
    "message": "Data ingested successfully",
    "timestamp": "2026-04-12T12:34:56"
}
```

---

### Spatial Analysis

#### 4. Synchronous Analysis

**Endpoint**: `POST /analyze`

**Description**: Perform spatial analysis operations synchronously

**Supported Operations**:
- `buffer`: Create buffer zones
- `intersect`: Find overlapping features
- `clip`: Extract features within bounds
- `dissolve`: Aggregate by attribute
- `hotspot_analysis`: Identify hotspots
- `cluster_analysis`: Group features

**Request**:
```json
{
    "operation": "buffer",
    "params": {
        "distance": 100,
        "units": "meters"
    }
}
```

**Response** (200 OK):
```json
{
    "status": 200,
    "data": {
        "operation": "buffer",
        "status": "completed",
        "result": {
            "features": 3,
            "geometry_type": "POLYGON"
        }
    },
    "message": "Analysis completed successfully",
    "timestamp": "2026-04-12T12:34:56"
}
```

#### 5. Asynchronous Analysis

**Endpoint**: `POST /analyze/async`

**Description**: Submit long-running analysis as background job

**Request**:
```json
{
    "operation": "kriging_interpolation",
    "params": {
        "variable": "temperature",
        "resolution": 0.01
    }
}
```

**Response** (202 Accepted):
```json
{
    "status": 202,
    "data": {
        "job_id": "job-12345678-1234-1234-1234-123456789012",
        "status": "pending",
        "operation": "kriging_interpolation",
        "check_url": "/jobs/job-12345678-1234-1234-1234-123456789012"
    },
    "message": "Job submitted for processing",
    "timestamp": "2026-04-12T12:34:56"
}
```

#### 6. Get Job Status

**Endpoint**: `GET /jobs/{job_id}`

**Description**: Retrieve status and results of async job

**Response** (200 OK):
```json
{
    "status": 200,
    "data": {
        "job_id": "job-12345678-1234-1234-1234-123456789012",
        "status": "completed",
        "operation": "kriging_interpolation",
        "progress": 100.0,
        "result": {
            "interpolated_values": [20.5, 20.3, 20.7],
            "variance": [0.5, 0.6, 0.4]
        },
        "error": null,
        "created_at": "2026-04-12T12:34:00",
        "completed_at": "2026-04-12T12:35:30"
    },
    "message": "Job status retrieved",
    "timestamp": "2026-04-12T12:35:31"
}
```

---

### Machine Learning

#### 7. Train Model

**Endpoint**: `POST /train`

**Description**: Train ML model for spatial prediction

**Request**:
```json
{
    "model_type": "forest",
    "target_variable": "temperature",
    "features": ["latitude", "longitude", "elevation"],
    "train_fraction": 0.8,
    "hyperparameters": {
        "n_trees": 100,
        "max_depth": 15
    }
}
```

**Response** (200 OK):
```json
{
    "status": 200,
    "data": {
        "model_id": "model-87654321-4321-4321-4321-210987654321",
        "model_type": "forest",
        "metrics": {
            "mae": 1.23,
            "rmse": 1.56,
            "r2": 0.92
        },
        "features": ["latitude", "longitude", "elevation"]
    },
    "message": "Model trained successfully",
    "timestamp": "2026-04-12T12:34:56"
}
```

#### 8. Make Predictions

**Endpoint**: `POST /predict`

**Description**: Generate predictions using trained model

**Request**:
```json
{
    "model_id": "model-87654321-4321-4321-4321-210987654321",
    "features": [
        [40.7128, -74.0060, 100],
        [40.7580, -73.9855, 105],
        [40.8566, -74.2090, 98]
    ]
}
```

**Response** (200 OK):
```json
{
    "status": 200,
    "data": {
        "model_id": "model-87654321-4321-4321-4321-210987654321",
        "predictions": [20.5, 21.3, 20.1],
        "confidence": [0.92, 0.89, 0.91]
    },
    "message": "Predictions generated",
    "timestamp": "2026-04-12T12:34:56"
}
```

---

### Visualization

#### 9. Generate Visualization

**Endpoint**: `POST /visualize`

**Description**: Create interactive map or chart

**Request**:
```json
{
    "type": "heatmap",
    "variable": "temperature",
    "colormap": "YlOrRd",
    "title": "Temperature Distribution"
}
```

**Response** (200 OK):
```json
{
    "status": 200,
    "data": {
        "visualization_type": "heatmap",
        "url": "/viz/viz-12345678.html",
        "format": "html",
        "size_bytes": 245670
    },
    "message": "Visualization generated",
    "timestamp": "2026-04-12T12:34:56"
}
```

---

### Data Export

#### 10. Export Data

**Endpoint**: `POST /export`

**Description**: Export analysis results in various formats

**Request**:
```json
{
    "format": "geojson",
    "variable": "temperature",
    "filter": {
        "min_value": 15,
        "max_value": 25
    }
}
```

**Response** (200 OK):
```json
{
    "status": 200,
    "data": {
        "format": "geojson",
        "download_url": "/downloads/results-12345678.geojson",
        "size_bytes": 567890,
        "feature_count": 1250
    },
    "message": "Export generated",
    "timestamp": "2026-04-12T12:34:56"
}
```

---

## Error Handling

### Error Response Format

All errors return a consistent JSON structure:

```json
{
    "status": 400,
    "data": {},
    "message": "Descriptive error message",
    "timestamp": "2026-04-12T12:34:56"
}
```

### HTTP Status Codes

| Code | Meaning | Example |
|------|---------|---------|
| 200 | OK | Successful request |
| 202 | Accepted | Job submitted for processing |
| 400 | Bad Request | Invalid parameters |
| 401 | Unauthorized | Missing/invalid token |
| 404 | Not Found | Resource not found |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Server error |

---

## Examples

### Example 1: Complete Analysis Workflow

```bash
#!/bin/bash

# 1. Authenticate
TOKEN=$(curl -s -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}' \
  | jq -r '.data.token')

# 2. Ingest data
curl -s -X POST http://localhost:8080/ingest \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "source": "NOAA",
    "format": "JSON",
    "data": {
      "latitude": [40.7, 40.8],
      "longitude": [-74.0, -74.1],
      "temperature": [20.5, 21.3]
    }
  }' | jq .

# 3. Analyze
curl -s -X POST http://localhost:8080/analyze \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "operation": "hotspot_analysis",
    "params": {"variable": "temperature"}
  }' | jq .

# 4. Visualize
curl -s -X POST http://localhost:8080/visualize \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "heatmap",
    "variable": "temperature"
  }' | jq .
```

### Example 2: Async Job Submission & Polling

```bash
#!/bin/bash

# Submit async job
JOB_RESPONSE=$(curl -s -X POST http://localhost:8080/analyze/async \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "operation": "kriging_interpolation",
    "params": {"variable": "temperature"}
  }')

JOB_ID=$(echo $JOB_RESPONSE | jq -r '.data.job_id')

# Poll for completion
while true; do
  STATUS=$(curl -s http://localhost:8080/jobs/$JOB_ID \
    -H "Authorization: Bearer $TOKEN" \
    | jq -r '.data.status')
  
  if [ "$STATUS" = "completed" ]; then
    echo "Job completed!"
    curl -s http://localhost:8080/jobs/$JOB_ID \
      -H "Authorization: Bearer $TOKEN" | jq '.data.result'
    break
  elif [ "$STATUS" = "failed" ]; then
    echo "Job failed!"
    break
  fi
  
  echo "Status: $STATUS..."
  sleep 5
done
```

### Example 3: ML Prediction

```python
import requests
import json

# Configuration
API_URL = "http://localhost:8080"
TOKEN = "your-token-here"
headers = {"Authorization": f"Bearer {TOKEN}"}

# Make prediction
response = requests.post(
    f"{API_URL}/predict",
    headers=headers,
    json={
        "model_id": "model-xyz",
        "features": [
            [40.7128, -74.0060, 100],
            [40.7580, -73.9855, 105]
        ]
    }
)

predictions = response.json()["data"]["predictions"]
print(f"Predictions: {predictions}")
```

---

## Deployment & Configuration

See `DEPLOYMENT_GUIDE.md` for:
- Docker deployment
- Kubernetes setup
- Environment variables
- Production configuration
- Scaling & performance tuning
- Monitoring & logging

---

**Last Updated**: April 12, 2026  
**API Version**: 1.0.0  
**Status**: Production Ready
