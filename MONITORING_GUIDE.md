# Advanced Monitoring & Observability Guide

## Overview

Complete monitoring stack with Prometheus, Grafana, ELK, and Jaeger for observability.

## Components

### Prometheus
- Metrics collection and storage
- Multi-target scraping
- Alert rules and evaluation
- 15-second scrape interval

### Grafana
- Metrics visualization
- Custom dashboards
- Real-time monitoring
- Alert management

### ELK Stack
- **Elasticsearch**: Log storage and indexing
- **Logstash**: Log aggregation and processing
- **Kibana**: Log visualization and analysis

### Jaeger (Optional)
- Distributed tracing
- Request flow tracking
- Performance analysis

## Quick Start

```bash
# Deploy monitoring namespace
kubectl create namespace monitoring

# Deploy Prometheus
kubectl apply -f monitoring/prometheus/

# Deploy Grafana
kubectl apply -f monitoring/grafana/

# Deploy ELK Stack
kubectl apply -f monitoring/elastic/

# Access services
kubectl port-forward -n monitoring svc/prometheus 9090:9090
kubectl port-forward -n monitoring svc/grafana 3000:3000
kubectl port-forward -n monitoring svc/kibana 5601:5601
```

## Metrics Tracked

### API Metrics
- Request rate and latency
- Error rates and types
- Response time percentiles
- Endpoint-specific metrics

### Database Metrics
- Connection count
- Query latency
- Transaction metrics
- Replication lag

### Infrastructure Metrics
- CPU and memory usage
- Disk space and I/O
- Network traffic
- Pod restart counts

## Alert Rules

Critical alerts:
- API Down (1min)
- Database Down (1min)
- High Error Rate (5%)
- High Response Time (>1s p95)

Warning alerts:
- High CPU/Memory
- Low Disk Space
- High Connection Count
- Pod Restarting Frequently

## Dashboards

Pre-built dashboards for:
- System Overview
- API Performance
- Database Health
- Pod Status
- Node Resources

## Log Aggregation

All pod logs automatically collected:
- API logs
- Web UI logs
- Database logs
- System logs

Query in Kibana using:
- Kubernetes namespace
- Pod name
- Log level
- Timestamp ranges

## Custom Metrics

Add custom metrics to API:

```julia
using Prometheus

gauge = Prometheus.Gauge("custom_metric", "Description")
gauge.set(value)

counter = Prometheus.Counter("events_total", "Total events")
counter.inc()

histogram = Prometheus.Histogram("latency_seconds", "Request latency")
histogram.observe(duration)
```

---

See monitoring/ directory for complete configurations.
