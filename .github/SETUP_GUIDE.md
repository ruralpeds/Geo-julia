# GitHub Actions Setup Guide

## Quick Setup (5 minutes)

### 1. Add Secrets

Go to **Settings → Secrets and variables → Actions** and add:

```bash
# For Docker registry (optional, uses GITHUB_TOKEN by default)
# DOCKER_USERNAME=youruser
# DOCKER_PASSWORD=yourtoken

# For deployment (if using automatic deployment)
# STAGING_HOST=staging.example.com
# STAGING_USER=deploy
# STAGING_DEPLOY_KEY=<private-key>
# PROD_HOST=production.example.com
# PROD_USER=deploy
# PROD_DEPLOY_KEY=<private-key>
# PROD_DB_PASSWORD=<strong-password>
# PROD_REDIS_PASSWORD=<strong-password>
```

### 2. Enable GitHub Actions

1. Go to **Settings → Actions → General**
2. Select "Allow all actions and reusable workflows"
3. Save

### 3. Configure Branch Protection

1. Go to **Settings → Branches → main**
2. Require PR reviews
3. Require status checks to pass:
   - `api-tests`
   - `web-tests`
   - `security-scan`
   - `code-quality`
4. Save

### 4. Test Workflows

Trigger manually to verify setup:

```bash
# Using GitHub CLI
gh workflow run ci.yml --ref main
gh workflow run docker.yml --ref main

# Or from web UI: Actions → Select workflow → Run workflow
```

## Complete Setup (30 minutes)

### Step 1: Container Registry

**Option A: GitHub Container Registry (GHCR)**

Already configured! Uses `GITHUB_TOKEN` automatically.

**Option B: Docker Hub**

1. Create Docker Hub account
2. Create access token: Settings → Security → New Access Token
3. Add secrets:
   ```
   DOCKER_USERNAME=yourusername
   DOCKER_PASSWORD=youraccesstoken
   REGISTRY_URL=docker.io
   ```

### Step 2: Deployment Infrastructure

For automatic deployment, set up servers:

**Staging Server**:
```bash
# SSH setup
ssh-keygen -t rsa -b 4096 -f ~/.ssh/geo-staging-key
ssh-copy-id -i ~/.ssh/geo-staging-key deploy@staging.example.com

# Get private key for GitHub
cat ~/.ssh/geo-staging-key | base64 -w0
# Copy output to STAGING_DEPLOY_KEY secret
```

**Production Server**:
```bash
# SSH setup
ssh-keygen -t rsa -b 4096 -f ~/.ssh/geo-prod-key
ssh-copy-id -i ~/.ssh/geo-prod-key deploy@production.example.com

# Get private key for GitHub
cat ~/.ssh/geo-prod-key | base64 -w0
# Copy output to PROD_DEPLOY_KEY secret
```

### Step 3: Environment Protection

1. Go to **Settings → Environments**
2. Create "staging" environment
3. Create "production" environment
4. For production, enable:
   - Required reviewers (add team members)
   - Deployment branches (allow main/develop)
   - Environment secrets (PROD_DB_PASSWORD, PROD_REDIS_PASSWORD)

### Step 4: Enable Branch Protection Rules

For main branch:
1. **Settings → Branches → Add rule**
2. Branch name pattern: `main`
3. Enable:
   - ✅ Require pull request reviews
   - ✅ Require status checks to pass
   - ✅ Require branches to be up to date
   - ✅ Require code to be scanned
   - ✅ Require deployment to succeed
4. Save

### Step 5: Configure Notifications

**GitHub Notifications**:
1. Settings → Notifications → Actions
2. Choose notification preference

**Slack Integration**:
1. Install [Slack GitHub Action](https://github.com/slackapi/slack-github-action)
2. Create Slack webhook
3. Add to workflows

**Email Alerts**:
1. Settings → Notifications → Email
2. Choose watch preferences

## Local Testing

Test workflows locally before committing:

### Test Julia Tests

```bash
julia --project="." -e 'using Pkg; Pkg.test()'
```

### Test Node Tests

```bash
cd web-ui
npm install
npm run test
npm run lint
npm run build
```

### Test Docker Build

```bash
# Build API
docker build -f Dockerfile -t geo-api:test .

# Build Web UI
docker build -f web-ui/Dockerfile -t geo-web:test .

# Run tests
docker-compose up -d
docker-compose exec api curl http://localhost:8080/health
```

## Customization

### Modify Test Matrix

Edit `ci.yml`:
```yaml
strategy:
  matrix:
    julia-version: ['1.8', '1.9', '1.10']
```

### Change Deployment Branches

Edit `deploy.yml`:
```yaml
on:
  push:
    branches: [ main, staging, develop ]
```

### Adjust Schedules

Edit workflows to change cron:
```yaml
schedule:
  - cron: '0 2 * * *'  # Daily at 2 AM UTC
```

### Add Custom Steps

Insert in any workflow:
```yaml
- name: Custom step
  run: |
    echo "Custom commands here"
```

## Debugging

### Enable Debug Logging

```bash
# Run workflow with debug
ACTIONS_STEP_DEBUG=true gh run watch <run-id>
```

### View Detailed Logs

1. Go to **Actions → Workflow Run**
2. Click job name
3. Expand step to see full output

### Check Secrets

**⚠️ Secrets are masked in logs!**

To debug:
```yaml
- name: Debug (remove before production)
  env:
    SECRET: ${{ secrets.MY_SECRET }}
  run: |
    echo "Secret length: ${#SECRET}"  # Shows only length, not value
```

## Common Issues

### "Permission Denied" on SSH Deploy

**Solution**: 
1. Ensure SSH key is RSA format
2. Check `.ssh/authorized_keys` on server
3. Verify key permissions: `chmod 600 ~/.ssh/authorized_keys`

### Docker Build Timeout

**Solution**:
1. Increase timeout in workflow
2. Use buildx cache for faster builds
3. Split into smaller jobs

### Tests Flaky/Intermittent

**Solution**:
1. Add retry logic
2. Increase timeouts
3. Check test dependencies
4. Run locally to reproduce

### Workflow Not Triggering

**Solution**:
1. Check branch name matches trigger
2. Verify workflow file syntax
3. Check file is in `.github/workflows/`
4. Ensure file has `.yml` or `.yaml` extension

## Security Best Practices

### Secrets Management

✅ **DO**:
- Use GitHub Secrets for sensitive data
- Rotate secrets regularly
- Use least-privilege permissions
- Enable environment protection

❌ **DON'T**:
- Commit secrets to repository
- Print secrets in logs
- Share secrets in emails
- Use same secret across environments

### Access Control

```yaml
permissions:
  contents: read
  packages: write
  id-token: write  # For OIDC
```

### Dependency Security

- Use specific action versions (no `@main`)
- Regularly update actions
- Review action code before using
- Use GitHub's dependency scanning

## Monitoring & Analytics

### View Workflow Statistics

```bash
# List recent runs
gh run list --limit 10

# Get run duration
gh run view <run-id> --json conclusion,durationMinutes
```

### Cost Monitoring

1. **Settings → Billing and plans**
2. **Actions** tab shows usage
3. Monitor for cost overruns

### Performance Optimization

View in **Actions** tab:
- Job duration trends
- Most time-consuming jobs
- Cache effectiveness
- Parallel job efficiency

## Integration with CI/CD Tools

### With GitLab CI

Use GitHub Actions to trigger GitLab pipelines via webhook

### With Jenkins

Use GitHub Actions to trigger Jenkins jobs

### With Cloud Providers

- **AWS**: Use AWS credentials for deployment
- **GCP**: Use Google Cloud service account
- **Azure**: Use Azure credentials

## Next Steps

1. ✅ Add secrets
2. ✅ Configure branch protection
3. ✅ Test workflows locally
4. ✅ Run first workflow
5. ✅ Monitor execution
6. ✅ Set up notifications
7. ✅ Configure deployment (optional)
8. ✅ Document custom workflows

## Support

- [GitHub Actions Docs](https://docs.github.com/actions)
- [GitHub CLI Help](https://cli.github.com)
- [Repository Issues](https://github.com/timothyhartzog/Geo-julia/issues)

---

**Setup Time**: ~30 minutes  
**Maintenance**: ~5 minutes/week  
**Cost**: Free for public repos
