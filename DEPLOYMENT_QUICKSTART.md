# Yield Optimizer - Quick Deployment Guide

A condensed guide for quickly deploying the Yield Optimizer to Kubernetes.

## Quick Prerequisites Check

```bash
# Check all prerequisites at once
kubectl version --short
helm version --short
docker --version
```

## 1. Initial Setup (One-time)

```bash
# Clone and navigate
git clone <repository-url> && cd yield-optimizer

# Create namespace
kubectl apply -f k8s/manifests/namespace.yaml

# Create secrets (replace with your values)
kubectl create secret generic yield-optimizer-db-secret \
  -n yield-optimizer \
  --from-literal=database-url='your-supabase-url' \
  --from-literal=database-password='your-password'
```

## 2. Build & Push Images

```bash
# Set your registry
export REGISTRY_URL="your-registry.com"
export IMAGE_TAG="latest"

# Build and push
cd services/monitor
docker build -t $REGISTRY_URL/yield-optimizer/monitor:$IMAGE_TAG .
docker push $REGISTRY_URL/yield-optimizer/monitor:$IMAGE_TAG
cd ../..

# Update image in values file
sed -i "s|repository:.*|repository: $REGISTRY_URL/yield-optimizer/monitor|g" helm/yield-optimizer/values-*.yaml
sed -i "s|tag:.*|tag: $IMAGE_TAG|g" helm/yield-optimizer/values-*.yaml
```

## 3. Deploy

### Development
```bash
./deploy.sh dev install
```

### Production
```bash
./deploy.sh prod install
```

## 4. Verify Deployment

```bash
# Check status
./deploy.sh dev status

# Test locally
kubectl port-forward -n yield-optimizer svc/yield-optimizer-monitor 8080:8080 &
curl http://localhost:8080/health
```

## 5. Access Application

### Development (Port Forward)
```bash
./deploy.sh dev port-forward
# Access at http://localhost:8080
```

### Production (Via Ingress)
```bash
# Get ingress URL
kubectl get ingress -n yield-optimizer
# Access at https://yield-optimizer.yourdomain.com
```

## Common Commands

```bash
# View logs
./deploy.sh dev logs

# Upgrade deployment
./deploy.sh dev upgrade

# Scale manually
kubectl scale deployment yield-optimizer-monitor -n yield-optimizer --replicas=3

# Restart pods
kubectl rollout restart deployment/yield-optimizer-monitor -n yield-optimizer

# Uninstall
./deploy.sh dev uninstall
```

## Quick Troubleshooting

```bash
# Pod not starting?
kubectl describe pod -n yield-optimizer -l app.kubernetes.io/name=yield-optimizer

# Connection issues?
kubectl logs -n yield-optimizer -l app.kubernetes.io/name=yield-optimizer --tail=50

# Resource issues?
kubectl top pods -n yield-optimizer
kubectl describe resourcequota -n yield-optimizer
```

## Emergency Rollback

```bash
# List versions
helm history yield-optimizer -n yield-optimizer

# Rollback
helm rollback yield-optimizer -n yield-optimizer

# Force restart
kubectl delete pods -n yield-optimizer -l app.kubernetes.io/name=yield-optimizer
```