# CI/CD Pipeline Guide

## Overview

This document describes the complete GitHub Actions CI/CD pipeline for the GeoSpatial Analysis Engine. The pipeline automates testing, building, and deploying the application.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    GitHub Repository                     │
│                                                           │
│  ┌────────────────────────────────────────────────────┐ │
│  │                   GitHub Actions                    │ │
│  │                                                     │ │
│  │  1. CI Pipeline         (ci.yml)                  │ │
│  │     └─ Tests & Linting                            │ │
│  │                                                     │ │
│  │  2. Docker Build        (docker.yml)              │ │
│  │     └─ Build & Push to Registry                   │ │
│  │                                                     │ │
│  │  3. Deployment          (deploy.yml)              │ │
│  │     └─ Staging & Production                       │ │
│  │                                                     │ │
│  │  4. Performance         (performance.yml)          │ │
│  │     └─ Benchmarks & Load Tests                    │ │
│  │                                                     │ │
│  │  5. Status Checks       (status-checks.yml)       │ │
│  │     └─ Health & Monitoring                        │ │
│  │                                                     │ │
│  └────────────────────────────────────────────────────┘ │
│                          ↓                               │
│              ┌──────────────────────────┐               │
│              │   Container Registry     │               │
│              │   (ghcr.io)             │               │
│              └──────────────────────────┘               │
└─────────────────────────────────────────────────────────┘
```

## Workflows

### 1. CI Pipeline (`ci.yml`)

**Trigger**: On every push and pull request

**Jobs**:
- **API Tests**: Unit tests and integration tests for Julia backend
  - Tests against multiple Julia versions (1.8, 1.9)
  - Database integration tests
  - API endpoint tests

- **Web Tests**: Frontend testing and build
  - ESLint linting
  - Unit tests
  - Build verification
  - Build size checks

- **Security Scan**: Vulnerability scanning
  - Trivy filesystem scan
  - npm audit
  - GitHub CodeQL integration

- **Code Quality**: Code analysis
  - ESLint analysis
  - Code quality metrics

**Output**:
- Test results and coverage reports
- Build artifacts
- Security scan results
- Code quality metrics

**Status Check**: Must pass before merge

### 2. Docker Build (`docker.yml`)

**Trigger**: On push to main/develop, tags, or pull requests

**Jobs**:
- **Build API**: Build Julia API Docker image
  - Multi-stage build for optimization
  - Cache optimization with buildx
  - Push to container registry (ghcr.io)

- **Build Web**: Build Vue.js Web UI Docker image
  - Multi-stage build with Node builder
  - Alpine-based Nginx production image
  - Automatic tagging

- **Image Scan**: Scan images for vulnerabilities
  - Trivy vulnerability scanning
  - SARIF report generation
  - Security alerts

**Tags Applied**:
- `develop`: For develop branch
- `main-<sha>`: For main branch
- `latest`: For main branch
- `v*`: For git tags

**Registry**: ghcr.io

### 3. Deployment (`deploy.yml`)

**Trigger**: On push to main/develop or manual workflow_dispatch

**Stages**:

**Staging Deployment**:
- Automatic on develop branch push
- Deploy to staging environment
- Run smoke tests
- Validation before production

**Production Deployment**:
- Requires environment approval
- Automatic on main branch push or git tag
- Create database backup before deploy
- Health checks after deployment
- Rollback capability

**Environment Approval Required**: Yes (for production)

**Process**:
1. Extract version from tag or commit
2. Configure environment variables
3. Backup database
4. Pull latest images
5. Update containers
6. Run health checks
7. Create deployment record

### 4. Performance Testing (`performance.yml`)

**Trigger**: 
- On every push to main/develop
- On pull requests
- Daily scheduled tests
- Manual trigger

**Jobs**:
- **Unit Tests**: Performance unit tests
- **Integration Tests**: API and database performance
- **Load Tests**: Apache Bench load testing
- **Benchmark Comparison**: Compare with baseline
- **Resource Usage**: Monitor CPU and memory

**Metrics Tracked**:
- API response time
- Database query time
- Memory usage
- CPU usage
- Request throughput

**Reports**:
- Performance comparison graphs
- Baseline comparison
- Resource usage charts

### 5. Status Checks (`status-checks.yml`)

**Trigger**: 
- Every 30 minutes (scheduled)
- Manual workflow_dispatch

**Checks**:
- API health endpoint
- Web UI health endpoint
- Database connectivity
- Redis cache connectivity

**Reports**:
- Service health status
- Dependency status
- Uptime metrics
- Dependency updates available

**Frequency**: Every 30 minutes

## Secrets Configuration

Add these secrets in GitHub Settings → Secrets:

```
STAGING_HOST              = staging-server.example.com
STAGING_USER              = deploy_user
STAGING_DEPLOY_KEY        = <SSH private key for staging>

PROD_HOST                 = production-server.example.com
PROD_USER                 = deploy_user
PROD_DEPLOY_KEY           = <SSH private key for production>

PROD_DB_PASSWORD          = <Strong database password>
PROD_REDIS_PASSWORD       = <Strong Redis password>
```

## Environment Variables

Configure in GitHub Settings → Variables:

```
REGISTRY                  = ghcr.io
IMAGE_NAME                = timothyhartzog/geo-julia
STAGING_API_URL           = https://api-staging.example.com
PRODUCTION_API_URL        = https://api.example.com
```

## Workflow Triggers

### Manual Trigger

Trigger any workflow manually from Actions tab:

```bash
# Using GitHub CLI
gh workflow run ci.yml --ref main

# Or from web UI: Actions → Select Workflow → Run workflow
```

### Scheduled Triggers

- **Performance tests**: Daily at 2 AM UTC
- **Status checks**: Every 30 minutes
- **Custom schedules**: Edit cron expressions in workflow files

### Event Triggers

| Event | Trigger |
|-------|---------|
| `push` | Any branch |
| `pull_request` | Any PR |
| `workflow_dispatch` | Manual trigger |
| `schedule` | Cron schedule |
| `tags` | Git tags (v*) |

## Build Status Badge

Add to README.md:

```markdown
![CI Status](https://github.com/timothyhartzog/Geo-julia/workflows/CI%20-%20Test%20%26%20Build/badge.svg)
![Docker Build](https://github.com/timothyhartzog/Geo-julia/workflows/Docker%20-%20Build%20%26%20Push/badge.svg)
![Deployment](https://github.com/timothyhartzog/Geo-julia/workflows/Deploy%20-%20Staging%20%26%20Production/badge.svg)
```

## Monitoring Pipeline

### View Workflow Runs

```bash
# List all workflow runs
gh run list

# View specific workflow
gh run view <run-id>

# Watch workflow in real-time
gh run watch <run-id>

# Download artifacts
gh run download <run-id> --name <artifact-name>
```

### Check Job Status

Each workflow displays:
- ✅ Passed jobs (green)
- ❌ Failed jobs (red)
- ⏳ Running jobs (yellow)
- ⊘ Skipped jobs (gray)

### View Logs

```bash
# View workflow logs
gh run view <run-id> --log

# View specific job logs
gh run view <run-id> --log-level debug
```

## Troubleshooting

### Pipeline Failures

1. **Check logs**: Click on failed job to see error details
2. **Review changes**: Verify code changes didn't break tests
3. **Check dependencies**: Ensure dependencies are available
4. **Run locally**: Run same tests locally before pushing

### Common Issues

| Issue | Solution |
|-------|----------|
| Tests fail | Run tests locally: `julia --project=. -e 'using Pkg; Pkg.test()'` |
| Docker build fails | Check Dockerfile syntax: `docker build -f Dockerfile .` |
| Deployment fails | Verify SSH keys and server connectivity |
| Performance regression | Compare with baseline, check for inefficiencies |
| Health checks timeout | Verify service startup time, increase timeout |

### Debug Mode

Add debug logging to workflows:

```yaml
jobs:
  debug:
    runs-on: ubuntu-latest
    steps:
      - name: Enable debug
        run: echo "::debug::Debug message"
```

## Best Practices

### 1. Keep Workflows Fast

- Cache dependencies
- Run tests in parallel
- Use matrix for multiple versions
- Skip unnecessary jobs with conditions

### 2. Secure Secrets

- Never commit secrets to repo
- Use GitHub Secrets for sensitive data
- Rotate secrets regularly
- Use environment protection rules

### 3. Clear Naming

- Use descriptive job names
- Add comments to complex steps
- Document required environment variables
- Use consistent formatting

### 4. Monitoring

- Set up GitHub Actions alerts
- Monitor action execution time
- Track failure rates
- Review logs regularly

### 5. Maintenance

- Update action versions regularly
- Review and update dependencies
- Remove unused workflows
- Archive old artifacts

## Performance Optimization

### Caching Strategy

```yaml
- uses: actions/cache@v3
  with:
    path: ~/.julia/packages
    key: julia-${{ hashFiles('Project.toml') }}
```

### Parallel Jobs

```yaml
strategy:
  matrix:
    version: ['1.8', '1.9']
  max-parallel: 2
```

### Conditional Execution

```yaml
if: github.event_name == 'push' && github.ref == 'refs/heads/main'
```

## Advanced Features

### Artifact Management

```bash
# Download artifacts
gh run download <run-id> --pattern "test-results-*"

# Retention policies
# Default: 90 days (configurable in Settings)
```

### Workflow Approval

```yaml
environment:
  name: production
  url: https://example.com
```

Requires manual approval before running environment jobs.

### Custom Actions

Create reusable actions in `.github/actions/`:

```yaml
name: 'Custom Action'
description: 'Description'
runs:
  using: 'composite'
  steps:
    - run: echo "Hello"
```

## Cost Optimization

### GitHub Actions Pricing

- **Public repos**: Free unlimited minutes
- **Private repos**: 2,000 minutes/month free
- **Storage**: 1GB artifacts free per month

### Optimization Tips

- Use caching to reduce build time
- Parallelize independent jobs
- Use smaller runners when possible
- Clean up old artifacts
- Skip unnecessary workflows

## Integration with Monitoring

### Status Page Integration

Connect to status pages:
- [Statuspage.io](https://statuspage.io)
- [Atlassian Status](https://status.atlassian.com)
- Custom webhooks

### Slack Notifications

```yaml
- uses: slackapi/slack-github-action@v1
  with:
    payload: |
      {
        "text": "Deployment ${{ job.status }}"
      }
```

### PagerDuty Integration

```yaml
- name: Trigger PagerDuty
  if: failure()
  uses: morrissimo/pagerduty-action@v1
  with:
    event-action: 'trigger'
```

## Support & Resources

- [GitHub Actions Docs](https://docs.github.com/actions)
- [Workflow Syntax Reference](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [GitHub CLI Reference](https://cli.github.com/manual)
- [Actions Marketplace](https://github.com/marketplace?type=actions)

---

**Version**: 1.0.0  
**Last Updated**: April 13, 2026  
**Status**: Production Ready
