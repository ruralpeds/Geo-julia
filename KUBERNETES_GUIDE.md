# Kubernetes Deployment Guide

## Overview

Complete Kubernetes setup for the GeoSpatial Analysis Engine with:
- Auto-scaling deployments
- StatefulSet for databases
- Ingress for routing
- Persistent volumes
- Health checks
- Resource quotas

## Architecture

```
Internet
   ↓
Ingress (SSL/TLS)
   ├→ Web Service (2-3 replicas)
   └→ API Service (2-10 replicas with HPA)
      ├→ PostgreSQL StatefulSet
      └→ Redis Deployment
```

## Quick Start

### 1. Prerequisites

```bash
# Install tools
kubectl version --client
helm version
kustomize version

# Create cluster
kind create cluster --name geo-engine
# OR
minikube start --memory=8192 --cpus=4
```

### 2. Deploy Base

```bash
# Apply to cluster
kubectl apply -k k8s/base

# Verify pods
kubectl get pods -n geo-engine
kubectl get svc -n geo-engine
```

### 3. Deploy Environment-Specific

```bash
# Development
kubectl apply -k k8s/overlays/dev

# Production
kubectl apply -k k8s/overlays/production
```

## Kustomize Structure

```
k8s/
├── base/                 # Base configuration
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── postgres-*
│   ├── redis-*
│   ├── api-*
│   ├── web-*
│   └── ingress.yaml
├── overlays/
│   ├── dev/
│   ├── staging/
│   └── production/
```

## Helm Charts (Optional)

Create Helm charts for easier management:

```bash
helm create geo-engine
# Generate package
helm package geo-engine
# Deploy
helm install geo-engine ./geo-engine-1.0.0.tgz
```

## Auto-Scaling

HPA (Horizontal Pod Autoscaler) configured:
- API: 2-10 replicas based on CPU/Memory
- Web: 1-5 replicas based on CPU

```bash
# Check HPA status
kubectl get hpa -n geo-engine
kubectl describe hpa api-hpa -n geo-engine
```

## Persistent Storage

PostgreSQL and Redis use PVCs:

```bash
# Check PVCs
kubectl get pvc -n geo-engine

# Backup database
kubectl exec postgres-0 -n geo-engine -- \
  pg_dump -U geoadmin geospatial > backup.sql
```

## Monitoring

Deploy Prometheus and Grafana (Phase 10):

```bash
# Add monitoring
kubectl apply -k monitoring/

# Access Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80
```

## Troubleshooting

```bash
# View logs
kubectl logs -n geo-engine deploy/api

# Describe pod
kubectl describe pod -n geo-engine <pod-name>

# Debug pod
kubectl debug -n geo-engine <pod-name> -it --image=busybox
```

---

For complete details, see k8s/ directory files.
