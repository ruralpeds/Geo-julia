# Docker Quick Start Guide

## One-Command Startup

```bash
# Clone and start everything
git clone https://github.com/timothyhartzog/Geo-julia.git
cd Geo-julia
docker-compose up -d
```

## Access Services

- **Web UI**: http://localhost:3000 (admin/changeme)
- **API**: http://localhost:8080
- **Database**: localhost:5432
- **Redis**: localhost:6379

## Common Commands

```bash
# View status
docker-compose ps

# View logs
docker-compose logs -f api          # API logs
docker-compose logs -f web          # Web UI logs
docker-compose logs -f postgres     # Database logs

# Stop services
docker-compose stop

# Restart services
docker-compose restart api

# Rebuild images
docker-compose build --no-cache

# Clean up volumes (WARNING: deletes data)
docker-compose down -v
```

## Health Checks

```bash
# API health
curl http://localhost:8080/health

# Web UI health
curl http://localhost:3000/health

# Database health
docker-compose exec postgres pg_isready -U geoadmin
```

## Backup & Restore

```bash
# Backup database
docker-compose exec postgres pg_dump -U geoadmin geospatial > backup.sql

# Restore database
docker-compose exec -T postgres psql -U geoadmin geospatial < backup.sql
```

## Production Deployment

See `DEPLOYMENT_GUIDE.md` for:
- SSL/TLS setup
- Performance tuning
- Monitoring & logging
- Database optimization
- Backup strategies
- Troubleshooting

---

**Version**: 1.0.0
