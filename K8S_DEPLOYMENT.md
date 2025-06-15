# Kubernetes Deployment Guide for Yield Optimizer

This guide covers deploying the HyperEVM Yield Optimizer on Kubernetes using Helm charts.

## 📋 Prerequisites

### Required Tools
- **Kubernetes cluster** (v1.19+)
- **Helm** (v3.8+)
- **kubectl** configured to access your cluster
- **Docker** (for building images)

### Recommended Add-ons
- **NGINX Ingress Controller**
- **cert-manager** (for TLS certificates)
- **Prometheus & Grafana** (for monitoring)

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│                 │    │                 │    │                 │
│   Ingress       │───▶│  Monitor Service│───▶│   Redis Cache   │
│   (nginx)       │    │   (Go Binary)   │    │   (Optional)    │
│                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │                 │
                       │ External Database│
                       │   (Supabase)    │
                       │   No PVC needed │
                       └─────────────────┘
```

## 🚀 Quick Start

### 1. Clone and Navigate
```bash
cd /Users/kenghong/claude-playground/yield-optimizer
```

### 2. Development Deployment
```bash
# Deploy to development environment
./deploy.sh dev install

# Check status
./deploy.sh dev status

# View logs
./deploy.sh dev logs
```

### 3. Access the Application
```bash
# Port forward to access locally
./deploy.sh dev port-forward

# Or access via ingress (if configured)
# http://yield-optimizer-dev.local
```

## 📁 Project Structure

```
yield-optimizer/
├── helm/yield-optimizer/           # Helm chart
│   ├── Chart.yaml                 # Chart metadata
│   ├── values.yaml                # Default values
│   ├── values-dev.yaml            # Development overrides
│   ├── values-prod.yaml           # Production overrides
│   └── templates/                 # Kubernetes templates
│       ├── monitor-deployment.yaml
│       ├── redis-deployment.yaml
│       ├── configmap.yaml
│       ├── secret.yaml
│       ├── services.yaml
│       └── ingress.yaml
├── k8s/manifests/                 # Raw Kubernetes manifests
│   └── namespace.yaml
├── services/monitor/              # Monitor service
│   ├── Dockerfile                # Container image
│   └── ...
└── deploy.sh                     # Deployment script
```

## 💾 Storage Strategy

### External Database (Supabase)
- ✅ **PostgreSQL**: Managed by Supabase (no PVC required)
- ✅ **High Availability**: Built-in replication and backups
- ✅ **Automatic Scaling**: Managed by Supabase
- ❌ **No K8s Storage**: No PersistentVolumeClaim needed

### Redis Cache (Optional)
- 🔧 **Development**: `persistence: false` (EmptyDir - faster startup)
- 🏭 **Production**: `persistence: true` (PVC for price cache persistence)
- 📊 **Usage**: Price data caching, temporary calculations

### Application Storage
- 📁 **Temporary Files**: EmptyDir volumes for `/tmp`
- 🔒 **Read-Only Root**: Security best practice
- 💾 **No Application Data**: Stateless service design

## ⚙️ Configuration

### Environment Variables

The application uses ConfigMaps and Secrets for configuration:

**ConfigMap (Non-sensitive):**
- `RPC_URL`: HyperEVM RPC endpoint
- `CHAIN_ID`: Network chain ID (998 for testnet)
- `LOG_LEVEL`: Logging level
- Performance settings

**Secret (Sensitive):**
- `DATABASE_URL`: PostgreSQL connection string
- `REDIS_URL`: Redis connection string
- `POSITION_MANAGER_ADDRESS`: Smart contract address
- `VAULT_ADDRESSES`: Comma-separated vault addresses

### Customizing Values

Create your own values file:

```yaml
# my-values.yaml
monitor:
  secretEnv:
    DATABASE_URL: "your-database-url"
    POSITION_MANAGER_ADDRESS: "0xYourContractAddress"
    VAULT_ADDRESSES: "0xVault1,0xVault2"
```

Deploy with custom values:
```bash
helm install yield-optimizer ./helm/yield-optimizer \\
  --namespace yield-optimizer \\
  --values my-values.yaml
```

## 🐳 Docker Image Build

### Build Monitor Service Image
```bash
cd services/monitor
docker build -t yield-optimizer/monitor:latest .
```

### Multi-architecture Build
```bash
docker buildx build --platform linux/amd64,linux/arm64 \\
  -t yield-optimizer/monitor:latest .
```

## 🌍 Environment-Specific Deployments

### Development Environment
- Single replica
- Lower resource limits
- Debug logging
- In-memory Redis (no persistence)
- Local ingress

```bash
./deploy.sh dev install
```

### Production Environment
- Multiple replicas with autoscaling
- Higher resource limits
- Info/warn logging
- Persistent Redis storage
- TLS-enabled ingress
- Security contexts

```bash
./deploy.sh prod install
```

## 📊 Monitoring & Observability

### Metrics Endpoint
The monitor service exposes Prometheus metrics on port 9090:
- `/metrics` - Application metrics
- `/health` - Health check endpoint

### ServiceMonitor
If Prometheus Operator is installed, a ServiceMonitor is created automatically:

```yaml
# Enable in values.yaml
monitor:
  metrics:
    enabled: true
```

### Logging
Structured JSON logging with configurable levels:
- `debug` - Detailed debugging information
- `info` - General information
- `warn` - Warning messages
- `error` - Error messages

View logs:
```bash
kubectl logs -n yield-optimizer -l app.kubernetes.io/component=monitor -f
```

## 🔒 Security

### Pod Security
- Non-root user (UID: 10001)
- Read-only root filesystem
- Dropped capabilities
- Security contexts applied

### Network Security
- Services use ClusterIP by default
- Ingress with TLS termination
- Network policies (optional)

### Secrets Management
- Kubernetes Secrets for sensitive data
- External secret management (recommended for production)

## 🔄 Common Operations

### Upgrade Deployment
```bash
./deploy.sh dev upgrade
```

### Scale Replicas
```bash
kubectl scale deployment yield-optimizer-monitor \\
  --namespace yield-optimizer --replicas=3
```

### Rolling Restart
```bash
kubectl rollout restart deployment/yield-optimizer-monitor \\
  --namespace yield-optimizer
```

### Check Resources
```bash
kubectl top pods --namespace yield-optimizer
```

## 🐛 Troubleshooting

### Pod Not Starting
```bash
# Check pod status
kubectl get pods -n yield-optimizer

# Describe pod for events
kubectl describe pod <pod-name> -n yield-optimizer

# Check logs
kubectl logs <pod-name> -n yield-optimizer
```

### Database Connection Issues
```bash
# Test database connectivity
kubectl run -it --rm debug --image=postgres:17-alpine \\
  --namespace yield-optimizer -- \\
  psql "your-database-url"
```

### Resource Issues
```bash
# Check resource quotas
kubectl describe resourcequota -n yield-optimizer

# Check node resources
kubectl top nodes
```

### Service Discovery
```bash
# Check services
kubectl get services -n yield-optimizer

# Test internal connectivity
kubectl run -it --rm debug --image=busybox \\
  --namespace yield-optimizer -- \\
  nslookup yield-optimizer-monitor
```

## 🔧 Advanced Configuration

### Custom Resource Limits
```yaml
monitor:
  resources:
    limits:
      cpu: 2000m
      memory: 2Gi
    requests:
      cpu: 500m
      memory: 512Mi
```

### Horizontal Pod Autoscaling
```yaml
monitor:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70
```

### Persistent Storage
```yaml
redis:
  persistence:
    enabled: true
    size: 5Gi
    storageClass: "fast-ssd"
```

### Ingress Configuration
```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: yield-optimizer.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: yield-optimizer-tls
      hosts:
        - yield-optimizer.yourdomain.com
```

## 📚 Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [HyperEVM Documentation](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm)
- [Prometheus Monitoring](https://prometheus.io/docs/)

## 🆘 Support

For issues and questions:
1. Check the troubleshooting section above
2. Review application logs
3. Check Kubernetes events
4. Verify configuration values

## 📄 License

This project is licensed under the MIT License.