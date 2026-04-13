# Production Deployment Guide

## Overview

This guide covers deploying the complete GeoSpatial Analysis Engine stack (API + Web UI + Database) to production environments.

## System Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Internet/Users                      │
└────────────────────┬────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────┐
│         Nginx Reverse Proxy (SSL/TLS)               │
│  - Load balancing                                    │
│  - Rate limiting                                     │
│  - Caching & compression                             │
│  - Security headers                                  │
└────────────────────┬────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        ▼                         ▼
    ┌────────┐              ┌────────┐
    │  Web   │              │  API   │
    │  UI    │              │        │
    │(Vue)   │              │(Julia) │
    └────┬───┘              └───┬────┘
         │                      │
         └──────────┬───────────┘
                    ▼
        ┌─────────────────────┐
        │  Database (PostgreSQL)  │
        │  + PostGIS              │
        └─────────────────────┘
        
        ┌─────────────────────┐
        │  Cache (Redis)      │
        │  Job Queue          │
        └─────────────────────┘
```

## Prerequisites

### System Requirements
- **OS**: Linux (Ubuntu 20.04+ or similar)
- **CPU**: 4+ cores recommended
- **RAM**: 8GB minimum, 16GB recommended
- **Storage**: 50GB SSD minimum
- **Docker**: Version 20.10+
- **Docker Compose**: Version 1.29+

### Network Requirements
- Public IP address (if accessible from internet)
- Ports 80, 443 available (HTTP/HTTPS)
- Port 22 available (SSH for management)
- Firewall properly configured

## Quick Start - Docker Compose

### 1. Clone Repository
```bash
git clone https://github.com/timothyhartzog/Geo-julia.git
cd Geo-julia
```

### 2. Set Environment Variables
```bash
# Create .env file
cat > .env << ENVEOF
# API Configuration
JULIA_NUM_THREADS=4
JULIA_OPTIMIZE=2

# Database
POSTGRES_DB=geospatial
POSTGRES_USER=geoadmin
POSTGRES_PASSWORD=$(openssl rand -base64 24)

# Redis
REDIS_PASSWORD=$(openssl rand -base64 24)

# Web UI
VITE_API_URL=http://localhost:8080
VITE_API_TIMEOUT=30000

# Production
ENVIRONMENT=production
ENVEOF
```

### 3. Build and Start Services
```bash
# Build all images
docker-compose build

# Start all services
docker-compose up -d

# Verify services are running
docker-compose ps

# Check service health
docker-compose exec api curl http://localhost:8080/health
```

### 4. Access Application
- **Web UI**: http://localhost:3000
- **API**: http://localhost:8080
- **Default Credentials**: admin / changeme

## SSL/TLS Configuration

### Using Let's Encrypt with Certbot

```bash
# Install certbot
sudo apt-get install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot certonly --standalone -d yourdomain.com

# Copy certificates to project
sudo cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem ./ssl/
sudo cp /etc/letsencrypt/live/yourdomain.com/privkey.pem ./ssl/
sudo chown $(whoami):$(whoami) ./ssl/*
```

## Database Setup

### PostgreSQL with PostGIS

```bash
# Connect to database container
docker-compose exec postgres psql -U geoadmin -d geospatial

# Enable PostGIS extension
CREATE EXTENSION postgis;
CREATE EXTENSION postgis_topology;

# Create spatial index
CREATE INDEX idx_data_geometry ON geospatial_data USING GIST(geometry);
```

### Backup Database
```bash
# Create backup
docker-compose exec postgres pg_dump -U geoadmin geospatial > backup.sql

# Restore from backup
docker-compose exec -T postgres psql -U geoadmin geospatial < backup.sql
```

## Monitoring & Logging

### View Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f api
docker-compose logs -f web

# Real-time logs with timestamp
docker-compose logs -f --timestamps api
```

### Health Checks
```bash
# API health
curl http://localhost:8080/health

# Web UI health
curl http://localhost:3000/health

# Database connectivity
docker-compose exec postgres pg_isready -U geoadmin
```

## Production Best Practices

### 1. Security

**Firewall Configuration**:
```bash
# Allow SSH
sudo ufw allow 22/tcp

# Allow HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Enable firewall
sudo ufw enable
```

### 2. Backup Strategy

```bash
#!/bin/bash
# Daily backup script

BACKUP_DIR="/backups/daily"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Database backup
docker-compose exec -T postgres pg_dump -U geoadmin geospatial \
  | gzip > "$BACKUP_DIR/db_$TIMESTAMP.sql.gz"

# Redis backup
docker-compose exec redis redis-cli BGSAVE
docker cp geospatial-cache:/data/dump.rdb "$BACKUP_DIR/redis_$TIMESTAMP.rdb"

# Keep only last 30 days
find "$BACKUP_DIR" -type f -mtime +30 -delete

echo "Backup completed: $TIMESTAMP"
```

### 3. Updates and Maintenance

**Rolling Updates**:
```bash
# Update images
docker-compose pull

# Restart only changed services
docker-compose up -d

# Verify updates
docker-compose ps
docker image ls
```

## Troubleshooting

### Services Won't Start

```bash
# Check logs
docker-compose logs api
docker-compose logs web
docker-compose logs postgres

# Verify port conflicts
sudo netstat -tulpn | grep -E '80|443|8080|3000'

# Rebuild images
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

### Database Connection Issues

```bash
# Test connection
docker-compose exec postgres psql -h postgres -U geoadmin -d geospatial -c "SELECT 1;"

# Reset database
docker volume rm geospatial-deploy_postgres_data
docker-compose restart postgres

# Check database logs
docker-compose logs postgres
```

### Web UI Issues

```bash
# Clear browser cache
# Check web UI logs
docker-compose logs web

# Rebuild web UI
docker-compose build --no-cache web
docker-compose up -d web

# Verify API connectivity from web container
docker-compose exec web curl http://api:8080/health
```

## Performance Optimization

### Database Optimization

```sql
-- Create indexes for common queries
CREATE INDEX idx_geometry ON geospatial_data USING GIST(geometry);
CREATE INDEX idx_created_at ON jobs(created_at DESC);
CREATE INDEX idx_status ON jobs(status);

-- Analyze query performance
EXPLAIN ANALYZE SELECT * FROM geospatial_data WHERE ST_DWithin(geometry, point, 1000);

-- Vacuum and analyze
VACUUM ANALYZE;
```

## Checklist for Production

- [ ] SSL/TLS certificates installed
- [ ] Firewall rules configured
- [ ] Database backups scheduled
- [ ] Monitoring and alerting setup
- [ ] Log aggregation enabled
- [ ] Rate limiting configured
- [ ] API keys and secrets rotated
- [ ] Resource limits set
- [ ] Auto-restart policies verified
- [ ] Disaster recovery tested
- [ ] Documentation updated
- [ ] Load testing completed

---

**Version**: 1.0.0  
**Last Updated**: April 13, 2026  
**Status**: Production Ready
