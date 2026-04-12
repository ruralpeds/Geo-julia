# GeoSpatial Analysis Engine - Deployment Guide

**Version**: 1.0.0  
**Date**: April 12, 2026  
**Status**: Production Ready

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Docker Deployment](#docker-deployment)
3. [Docker Compose](#docker-compose)
4. [Kubernetes Deployment](#kubernetes-deployment)
5. [Configuration](#configuration)
6. [Monitoring & Logging](#monitoring--logging)
7. [Performance Tuning](#performance-tuning)
8. [Security](#security)
9. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Local Development

```bash
# 1. Clone repository
git clone https://github.com/timothyhartzog/Geo-julia.git
cd Geo-julia

# 2. Start API server locally
julia --project=GeoSpatialEngine -e '
using GeoSpatialEngine
engine = GeoSpatialAnalysisEngine()
server = create_api_server(engine; host="127.0.0.1", port=8080)
start_api_server(server)
'

# 3. Test server
curl http://localhost:8080/health

# 4. Authenticate
curl -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}'
```

---

## Docker Deployment

### Build Docker Image

```bash
# Build image
docker build -t geospatial-engine:1.0.0 .

# Tag for registry
docker tag geospatial-engine:1.0.0 docker.io/yourorg/geospatial-engine:1.0.0

# Push to registry
docker push docker.io/yourorg/geospatial-engine:1.0.0
```

### Run Docker Container

```bash
# Basic execution
docker run -d \
  --name geospatial-api \
  -p 8080:8080 \
  geospatial-engine:1.0.0

# With environment variables
docker run -d \
  --name geospatial-api \
  -p 8080:8080 \
  -e HOST=0.0.0.0 \
  -e PORT=8080 \
  -e JULIA_NUM_THREADS=8 \
  -e JULIA_OPTIMIZE=2 \
  geospatial-engine:1.0.0

# With volume mounts for data persistence
docker run -d \
  --name geospatial-api \
  -p 8080:8080 \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/results:/app/results \
  geospatial-engine:1.0.0

# Check logs
docker logs -f geospatial-api

# Stop container
docker stop geospatial-api
```

---

## Docker Compose

### Start Multi-Service Stack

```bash
# Start all services
docker-compose up -d

# View service status
docker-compose ps

# View logs
docker-compose logs -f api

# Stop services
docker-compose down

# Restart services
docker-compose restart
```

### Services Included

1. **API Service** (Port 8080)
   - GeoSpatial Analysis Engine HTTP server
   - Health checks enabled
   - Thread pool: 4 (configurable)

2. **PostgreSQL Database** (Port 5432)
   - PostGIS extension enabled
   - Data persistence volume
   - Credentials: admin/geoadmin123

3. **Redis Cache** (Port 6379)
   - Job queue management
   - Result caching
   - Session storage

4. **Nginx Proxy** (Port 80/443)
   - Reverse proxy
   - Load balancing
   - SSL/TLS termination

### Configuration Files

**Environment Variables** (.env):
```bash
# API Configuration
HOST=0.0.0.0
PORT=8080
JULIA_NUM_THREADS=4
JULIA_OPTIMIZE=2

# Database
DB_HOST=postgres
DB_PORT=5432
DB_NAME=geospatial
DB_USER=geoadmin
DB_PASSWORD=geoadmin123

# Redis
REDIS_HOST=redis
REDIS_PORT=6379

# API
API_LOG_LEVEL=info
API_RATE_LIMIT=100
API_RATE_WINDOW=60
```

**Volumes**:
```bash
# Data directory
mkdir -p data results

# Set permissions
chmod 755 data results
```

---

## Kubernetes Deployment

### Create Deployment

**File**: `k8s-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: geospatial-engine
spec:
  replicas: 3
  selector:
    matchLabels:
      app: geospatial-engine
  template:
    metadata:
      labels:
        app: geospatial-engine
    spec:
      containers:
      - name: api
        image: docker.io/yourorg/geospatial-engine:1.0.0
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 2
            memory: 4Gi
          limits:
            cpu: 4
            memory: 8Gi
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /status
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
        env:
        - name: HOST
          value: "0.0.0.0"
        - name: PORT
          value: "8080"
        - name: JULIA_NUM_THREADS
          value: "4"
---
apiVersion: v1
kind: Service
metadata:
  name: geospatial-engine-service
spec:
  selector:
    app: geospatial-engine
  type: LoadBalancer
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: geospatial-engine-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: geospatial-engine
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### Deploy to Kubernetes

```bash
# Create namespace
kubectl create namespace geospatial

# Deploy services
kubectl apply -f k8s-deployment.yaml -n geospatial

# Check deployment status
kubectl get pods -n geospatial
kubectl get svc -n geospatial

# View logs
kubectl logs -f deployment/geospatial-engine -n geospatial

# Scale manually
kubectl scale deployment geospatial-engine --replicas=5 -n geospatial
```

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HOST` | `127.0.0.1` | Server bind address |
| `PORT` | `8080` | Server port |
| `JULIA_NUM_THREADS` | `4` | Julia thread pool size |
| `JULIA_OPTIMIZE` | `2` | Julia optimization level (0-3) |
| `LOG_LEVEL` | `info` | Logging level (debug, info, warn, error) |
| `RATE_LIMIT` | `100` | Max requests per window |
| `RATE_WINDOW` | `60` | Rate limit window in seconds |
| `DB_HOST` | `localhost` | Database host |
| `DB_PORT` | `5432` | Database port |
| `REDIS_HOST` | `localhost` | Redis host |
| `REDIS_PORT` | `6379` | Redis port |

### Configuration File (config.toml)

```toml
[server]
host = "0.0.0.0"
port = 8080
workers = 4

[performance]
julia_threads = 4
optimize_level = 2
max_memory_gb = 16

[api]
rate_limit = 100
rate_window_seconds = 60
timeout_seconds = 300

[logging]
level = "info"
format = "json"
output = "stdout"

[security]
require_auth = true
token_expiry_hours = 24
allow_origin = "*"
```

---

## Monitoring & Logging

### Health Checks

The engine includes built-in health checks:

```bash
# Health status
curl http://localhost:8080/health

# Server metrics
curl http://localhost:8080/status
```

### Prometheus Metrics (Future)

Metrics can be exposed at `/metrics`:

```bash
curl http://localhost:8080/metrics
```

### Logging

Logs are output to stdout (capture with Docker/K8s):

```bash
# View logs
docker logs geospatial-api

# Log levels
# DEBUG: Detailed debugging information
# INFO: General informational messages
# WARN: Warning messages
# ERROR: Error messages
```

### Structured Logging

Logs include:
- Timestamp (ISO 8601)
- Level (DEBUG, INFO, WARN, ERROR)
- Module/Function name
- Message
- Context (request ID, user ID, etc.)

Example:
```json
{
  "timestamp": "2026-04-12T12:34:56Z",
  "level": "INFO",
  "module": "api",
  "message": "Request completed",
  "duration_ms": 245,
  "request_id": "req-12345",
  "status": 200
}
```

---

## Performance Tuning

### Julia Optimization

```bash
# Optimization levels
JULIA_OPTIMIZE=0  # No optimization (debugging)
JULIA_OPTIMIZE=1  # Basic optimization
JULIA_OPTIMIZE=2  # Standard optimization (default)
JULIA_OPTIMIZE=3  # Aggressive optimization

# Thread pool sizing
export JULIA_NUM_THREADS=8  # Match CPU cores
```

### Memory Management

```bash
# Heap size
julia --heap-size-hint=8G

# Garbage collection
export JULIA_GC_THRESHOLD=0.8

# Memory pool
export JULIA_MEMORY_POOL_SIZE=2G
```

### Connection Pooling

For database/cache:
- Connection pool size: 10-20 per core
- Idle timeout: 30 seconds
- Max lifetime: 1 hour

### Caching Strategy

1. **Query Results**: Cache for 5 minutes
2. **Model Predictions**: Cache for 1 hour
3. **Visualization HTML**: Cache for 24 hours
4. **Job Results**: Cache until expiry

---

## Security

### Authentication

- Token-based authentication (Bearer tokens)
- Token expiration: 24 hours (configurable)
- Token refresh endpoint: `POST /auth/refresh`

### Authorization

- Role-based access control (RBAC)
- Roles: admin, analyst, viewer
- Scope-based permissions

### Network Security

```bash
# Firewall rules (example)
iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# TLS/SSL Configuration
# See nginx.conf for SSL setup
```

### Environment Variable Security

Sensitive data should be:
- Stored in environment variables
- Not committed to git
- Encrypted in transit
- Rotated regularly

Example `.env.example`:
```bash
# Copy and fill with real values
cp .env.example .env
chmod 600 .env
```

### Rate Limiting & DDoS Protection

- Per-user rate limiting: 100 req/min
- Per-IP rate limiting: 1000 req/min
- Connection timeout: 30 seconds
- Request size limit: 100 MB

---

## Troubleshooting

### Common Issues

#### 1. Port Already in Use

```bash
# Find process using port
lsof -i :8080
netstat -tlnp | grep :8080

# Kill process
kill -9 <PID>

# Or use different port
docker run -p 8081:8080 geospatial-engine:1.0.0
```

#### 2. Out of Memory

```bash
# Increase container memory
docker run -m 8g geospatial-engine:1.0.0

# Or in kubernetes
resources:
  limits:
    memory: "8Gi"
```

#### 3. Julia Precompilation Timeout

```bash
# Rebuild image with longer timeout
docker build --build-arg TIMEOUT=600 -t geospatial-engine:1.0.0 .

# Or precompile locally
julia --project=GeoSpatialEngine -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
```

#### 4. Database Connection Issues

```bash
# Test connection
docker exec geospatial-db psql -U geoadmin -d geospatial -c "SELECT 1"

# Check logs
docker logs geospatial-db

# Reset password
docker exec geospatial-db psql -U postgres -c "ALTER USER geoadmin PASSWORD 'newpassword'"
```

#### 5. Redis Connection Issues

```bash
# Test connection
docker exec geospatial-cache redis-cli ping

# Check memory usage
docker exec geospatial-cache redis-cli info memory

# Flush cache if needed
docker exec geospatial-cache redis-cli FLUSHALL
```

### Debug Mode

```bash
# Enable debug logging
export LOG_LEVEL=debug

# Run with verbose output
julia --project=GeoSpatialEngine -v start_api_server(server)

# Enable Julia debugger
julia --project=GeoSpatialEngine --debug=yes
```

### Performance Profiling

```bash
# CPU profiling
julia --project=GeoSpatialEngine -e '@profile start_api_server(server)'

# Memory profiling
julia --project=GeoSpatialEngine -e '@time start_api_server(server)'

# Flame graph
julia --project=GeoSpatialEngine -e 'profile_server()'
```

---

## Production Checklist

Before deploying to production:

- [ ] Environment variables configured
- [ ] Database credentials rotated
- [ ] SSL/TLS certificates installed
- [ ] Rate limiting configured
- [ ] Logging level set to INFO
- [ ] Health checks enabled
- [ ] Backup strategy in place
- [ ] Monitoring/alerting configured
- [ ] Load balancer configured
- [ ] Auto-scaling policies set
- [ ] Security audit completed
- [ ] Performance tests passed
- [ ] Disaster recovery plan documented
- [ ] Documentation updated

---

## Support & Resources

- **Documentation**: See API_DOCUMENTATION.md
- **GitHub**: https://github.com/timothyhartzog/Geo-julia
- **Issues**: https://github.com/timothyhartzog/Geo-julia/issues
- **Discussions**: https://github.com/timothyhartzog/Geo-julia/discussions

---

**Last Updated**: April 12, 2026  
**Version**: 1.0.0  
**Status**: Production Ready
