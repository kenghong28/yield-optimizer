# Yield Optimizer CI/CD Pipeline Documentation

This document describes the complete CI/CD pipeline implementation for the Yield Optimizer project.

## Overview

The CI/CD pipeline is built using GitHub Actions and consists of multiple workflows designed to ensure code quality, security, and reliable deployments across different environments.

## Pipeline Architecture

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Commit    │────►│     CI       │────►│    Build     │────►│   Deploy     │
│             │     │  (Testing)   │     │   (Docker)   │     │ (K8s/Helm)  │
└─────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
                            │                     │                     │
                            ▼                     ▼                     ▼
                    ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
                    │   Security   │     │    SBOM      │     │  Monitoring  │
                    │   Scanning   │     │ Generation   │     │   Updates    │
                    └──────────────┘     └──────────────┘     └──────────────┘
```

## Workflows

### 1. CI Pipeline (`ci.yml`)

**Trigger**: Push to main/develop, Pull requests

**Jobs**:
- **Lint**: Go code linting with golangci-lint
- **Test**: Unit and integration tests with coverage
- **Security**: Gosec and Trivy vulnerability scanning
- **Build**: Binary compilation and validation
- **Docker**: Container image building
- **K8s Validation**: Helm chart linting and manifest validation
- **SAST**: CodeQL static analysis
- **Dependency Check**: Outdated dependency detection

**Key Features**:
- Parallel job execution for faster feedback
- Test coverage reporting
- Security scanning at multiple levels
- Kubernetes manifest validation

### 2. CD Pipeline (`cd.yml`)

**Trigger**: Push to main, version tags, manual dispatch

**Jobs**:
- **Build & Push**: Docker image building and registry push
- **Security Scan**: Container vulnerability scanning
- **Deploy Dev**: Automatic deployment to development
- **Deploy Staging**: Deployment to staging after dev success
- **Deploy Prod**: Production deployment (tags only)
- **Rollback**: Manual rollback capability
- **Notifications**: Slack notifications

**Key Features**:
- Multi-environment deployment strategy
- Atomic deployments with automatic rollback
- SBOM generation for compliance
- Environment-specific approvals

### 3. Release Pipeline (`release.yml`)

**Trigger**: Manual workflow dispatch

**Jobs**:
- **Prepare Release**: Version bumping and changelog generation
- **Create Release**: Tag creation and GitHub release

**Key Features**:
- Semantic versioning support
- Automated changelog generation
- Pull request creation for release review

### 4. PR Checks (`pr-checks.yml`)

**Trigger**: Pull request events

**Jobs**:
- **Label**: Automatic PR labeling
- **Size Check**: PR size analysis
- **Commit Lint**: Conventional commit validation
- **Secret Scan**: Credential detection
- **License Check**: Dependency license validation
- **Docs Check**: Markdown linting and link checking
- **Performance**: Benchmark comparisons (optional)
- **Preview Deploy**: Temporary environment deployment
- **Auto-merge**: Dependabot PR automation

## Environment Strategy

### Development
- **Trigger**: Push to develop branch
- **Deployment**: Automatic
- **Validation**: Smoke tests
- **Rollback**: Automatic on failure

### Staging
- **Trigger**: Push to main branch
- **Deployment**: Automatic after dev success
- **Validation**: Integration test suite
- **Rollback**: Automatic on failure

### Production
- **Trigger**: Version tags (v*)
- **Deployment**: Manual approval required
- **Validation**: Full health checks
- **Rollback**: Manual trigger available

## Security Implementation

### 1. Code Security
- **Gosec**: Go security checker
- **CodeQL**: GitHub's semantic code analysis
- **TruffleHog**: Secret scanning

### 2. Container Security
- **Trivy**: Vulnerability scanning
- **Snyk**: Container analysis (optional)
- **SBOM**: Software bill of materials

### 3. Supply Chain Security
- **Dependency scanning**: Automated updates via Dependabot
- **License checking**: FOSSA integration
- **Signed commits**: GPG verification (recommended)

## Registry Configuration

The pipeline uses GitHub Container Registry (ghcr.io) by default:

```yaml
env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}
```

To use a different registry:

1. Update the `REGISTRY` environment variable
2. Configure authentication secrets
3. Update login action in workflows

## Secrets Configuration

Required GitHub Secrets:

```yaml
# Kubernetes Configuration
DEV_KUBECONFIG        # Base64 encoded kubeconfig for dev
STAGING_KUBECONFIG    # Base64 encoded kubeconfig for staging
PROD_KUBECONFIG       # Base64 encoded kubeconfig for production

# Optional Integration Secrets
SNYK_TOKEN           # Snyk vulnerability scanning
FOSSA_API_KEY        # License compliance
SLACK_WEBHOOK_URL    # Notifications
```

## Deployment Process

### 1. Development Deployment

```bash
# Automatic on push to develop
git push origin develop

# Manual trigger
gh workflow run cd.yml -f environment=dev
```

### 2. Staging Deployment

```bash
# Automatic on push to main
git push origin main
```

### 3. Production Deployment

```bash
# Create and push tag
git tag v1.0.0
git push origin v1.0.0

# Or use release workflow
gh workflow run release.yml -f version=v1.0.0 -f release_type=minor
```

## Rollback Procedures

### Automatic Rollback

Configured for dev and staging environments:
- Helm atomic deployments
- Automatic rollback on failure

### Manual Rollback

For production environments:

```bash
# Via GitHub Actions
gh workflow run cd.yml -f environment=prod

# Direct Helm rollback
helm rollback yield-optimizer -n yield-optimizer

# Or kubectl rollback
kubectl rollout undo deployment/yield-optimizer-monitor -n yield-optimizer
```

## Monitoring Integration

The CD pipeline automatically:
- Updates Grafana dashboards
- Configures environment-specific alerts
- Creates deployment annotations in monitoring

## Best Practices

### 1. Commit Messages
Follow conventional commits:
```
feat: add new APY calculation
fix: correct rebalancing logic
docs: update deployment guide
```

### 2. Branch Protection
Configure branch protection rules:
- Require PR reviews
- Require status checks
- Require up-to-date branches

### 3. Secret Management
- Use GitHub Secrets for sensitive data
- Rotate secrets regularly
- Never commit secrets to code

### 4. Testing Strategy
- Unit tests: Required for all new code
- Integration tests: Required for API changes
- Performance tests: For optimization PRs

## Troubleshooting

### CI Failures

1. **Lint failures**:
   ```bash
   golangci-lint run --fix
   ```

2. **Test failures**:
   ```bash
   go test -v ./...
   ```

3. **Security scan failures**:
   Check scan results in GitHub Security tab

### CD Failures

1. **Build failures**:
   Check Docker build logs

2. **Deploy failures**:
   ```bash
   kubectl describe pod -n yield-optimizer
   kubectl logs -n yield-optimizer -l app=yield-optimizer
   ```

3. **Rollback failures**:
   Check Helm release history

## Local Testing

Test workflows locally using [act](https://github.com/nektos/act):

```bash
# Install act
brew install act

# Test CI workflow
act push

# Test PR workflow
act pull_request

# Test with secrets
act -s GITHUB_TOKEN=$GITHUB_TOKEN
```

## Maintenance

### Updating Dependencies

Dependabot automatically creates PRs for:
- Go modules (weekly)
- GitHub Actions (weekly)
- Docker base images (weekly)
- Helm dependencies (weekly)

### Workflow Updates

1. Test changes in feature branch
2. Create PR with workflow changes
3. Test in dev environment first
4. Merge to main after validation

## Cost Optimization

- Use GitHub-hosted runners for public repos (free)
- Cache dependencies aggressively
- Run expensive checks only when needed
- Use matrix builds sparingly

## Future Enhancements

1. **GitOps Integration**: ArgoCD for declarative deployments
2. **Multi-region Deployments**: Geographic distribution
3. **Canary Deployments**: Progressive rollouts
4. **Cost Tracking**: Cloud spend monitoring
5. **Compliance Scanning**: SOC2/ISO compliance checks