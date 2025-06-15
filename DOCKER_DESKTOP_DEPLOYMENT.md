# Yield Optimizer - Docker Desktop Development Deployment

Quick guide for deploying yield-optimizer to Docker Desktop's Kubernetes for local development.

## Prerequisites

1. **Docker Desktop** - Install from https://www.docker.com/products/docker-desktop
2. **Enable Kubernetes** in Docker Desktop settings
3. **kubectl** and **helm** (install via Homebrew)

## 1. Enable Kubernetes in Docker Desktop

1. Open Docker Desktop
2. Go to Settings → Kubernetes
3. Check "Enable Kubernetes"
4. Click "Apply & Restart"
5. Wait for Kubernetes to start (green status)

## 2. Verify Setup

```bash
# Check Docker Desktop Kubernetes context
kubectl config current-context
# Should show: docker-desktop

# Verify cluster is running
kubectl cluster-info
kubectl get nodes
```

## 3. Build and Deploy

### Quick Start
```bash
# Build image locally
cd services/monitor
docker build -t yield-optimizer/monitor:dev .
cd ../..

# Create namespace
kubectl apply -f k8s/manifests/namespace.yaml

# Create dev secrets
kubectl create secret generic yield-optimizer-db-secret \
  -n yield-optimizer \
  --from-literal=database-url='your-supabase-dev-url' \
  --from-literal=database-password='your-dev-password'

# Deploy
./deploy.sh dev install
```

### Access the Application
```bash
# Port forward to access locally
kubectl port-forward -n yield-optimizer svc/yield-optimizer-monitor 8080:8080

# Open http://localhost:8080
```

## 4. Development Workflow

### Code → Build → Deploy Cycle
```bash
# 1. Make code changes in services/monitor/

# 2. Rebuild image
cd services/monitor
docker build -t yield-optimizer/monitor:dev .
cd ../..

# 3. Restart pods to pick up new image
kubectl rollout restart deployment/yield-optimizer-monitor -n yield-optimizer

# 4. Check deployment
kubectl get pods -n yield-optimizer -w
```

### Hot Reload Script
Create `dev-reload.sh`:
```bash
#!/bin/bash
echo "Rebuilding and redeploying..."
cd services/monitor
docker build -t yield-optimizer/monitor:dev .
cd ../..
kubectl rollout restart deployment/yield-optimizer-monitor -n yield-optimizer
kubectl rollout status deployment/yield-optimizer-monitor -n yield-optimizer
echo "Deployment ready!"
```

## 5. Useful Commands

### Viewing Logs
```bash
# Stream logs
kubectl logs -n yield-optimizer -l app.kubernetes.io/name=yield-optimizer -f

# Get specific pod logs
kubectl logs -n yield-optimizer deployment/yield-optimizer-monitor
```

### Debugging
```bash
# Get pod status
kubectl get pods -n yield-optimizer

# Describe pod for issues
kubectl describe pod -n yield-optimizer -l app.kubernetes.io/name=yield-optimizer

# Execute into pod
kubectl exec -it -n yield-optimizer deployment/yield-optimizer-monitor -- /bin/sh
```

### Service Access
```bash
# List services
kubectl get svc -n yield-optimizer

# Port forward to different port
kubectl port-forward -n yield-optimizer svc/yield-optimizer-monitor 3000:8080

# Access Redis (if deployed)
kubectl port-forward -n yield-optimizer svc/yield-optimizer-redis 6379:6379
```

## 6. Configuration for Docker Desktop

Update `helm/yield-optimizer/values-dev.yaml` for Docker Desktop:

```yaml
monitor:
  image:
    repository: yield-optimizer/monitor
    tag: dev
    pullPolicy: Never  # Important: Don't try to pull from registry

  replicaCount: 1  # Single replica for dev

  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"

redis:
  enabled: true
  persistence:
    enabled: false  # No persistence needed for dev

ingress:
  enabled: false  # Use port-forward instead

# Service type LoadBalancer works with Docker Desktop
service:
  type: LoadBalancer  # Docker Desktop provides localhost access
```

## 7. Advanced: Local Development with Hot Reload

### Option 1: Mount Source Code (for interpreted languages)
If your monitor service supported hot reload, you could mount source:

```yaml
# In deployment template
volumes:
- name: source-code
  hostPath:
    path: /path/to/yield-optimizer/services/monitor
    type: Directory

volumeMounts:
- name: source-code
  mountPath: /app
```

### Option 2: Use Tilt for Automated Rebuilds
```bash
# Install Tilt
brew install tilt-dev/tap/tilt

# Create Tiltfile
cat > Tiltfile <<EOF
# Build image
docker_build('yield-optimizer/monitor:dev', './services/monitor')

# Deploy manifests
k8s_yaml(['k8s/manifests/namespace.yaml'])
k8s_yaml(helm('./helm/yield-optimizer', values=['./helm/yield-optimizer/values-dev.yaml']))

# Port forward
k8s_resource('yield-optimizer-monitor', port_forwards=8080)
EOF

# Start Tilt
tilt up
```

### Option 3: Skaffold for DevOps
```bash
# Install Skaffold
brew install skaffold

# Create skaffold.yaml
cat > skaffold.yaml <<EOF
apiVersion: skaffold/v4beta1
kind: Config
build:
  artifacts:
  - image: yield-optimizer/monitor
    context: services/monitor
deploy:
  helm:
    releases:
    - name: yield-optimizer
      chartPath: helm/yield-optimizer
      valuesFiles:
      - helm/yield-optimizer/values-dev.yaml
portForward:
- resourceType: service
  resourceName: yield-optimizer-monitor
  namespace: yield-optimizer
  port: 8080
EOF

# Start development
skaffold dev
```

## 8. Docker Desktop Specific Features

### Access Services via LoadBalancer
```bash
# If service type is LoadBalancer, get external IP
kubectl get svc -n yield-optimizer yield-optimizer-monitor

# Docker Desktop maps LoadBalancer to localhost
# Access at http://localhost:<external-port>
```

### Resource Limits
Docker Desktop runs on your local machine, so be mindful:
```bash
# Check Docker Desktop resource usage
docker stats

# Adjust resources in Docker Desktop settings if needed
# Settings → Resources → Advanced
```

### Persistent Volumes
```bash
# Docker Desktop uses local host paths for PVs
kubectl get pv
kubectl get pvc -n yield-optimizer

# Data is stored in Docker Desktop's VM
```

## 9. Cleanup

```bash
# Remove application
helm uninstall yield-optimizer -n yield-optimizer

# Remove namespace
kubectl delete namespace yield-optimizer

# Remove Docker images (optional)
docker rmi yield-optimizer/monitor:dev

# Reset Kubernetes (if needed)
# Docker Desktop Settings → Kubernetes → Reset Kubernetes Cluster
```

## 10. Troubleshooting

### Image Not Found
```bash
# Ensure image is built locally
docker images | grep yield-optimizer

# Check imagePullPolicy is "Never" or "IfNotPresent"
```

### Pod Stuck in Pending
```bash
# Check events
kubectl get events -n yield-optimizer --sort-by='.lastTimestamp'

# Check resource constraints
kubectl describe node docker-desktop
```

### Service Not Accessible
```bash
# Check service endpoints
kubectl get endpoints -n yield-optimizer

# Verify port forwarding
lsof -i :8080
```

## Quick Start Script

Create `docker-desktop-dev.sh`:
```bash
#!/bin/bash
set -e

echo "=== Docker Desktop Kubernetes Development Setup ==="

# Check if Kubernetes is enabled
if ! kubectl config current-context | grep -q "docker-desktop"; then
    echo "Error: Please enable Kubernetes in Docker Desktop and set context to docker-desktop"
    exit 1
fi

# Build image
echo "Building Docker image..."
cd services/monitor
docker build -t yield-optimizer/monitor:dev .
cd ../..

# Create namespace
kubectl apply -f k8s/manifests/namespace.yaml

# Deploy
echo "Deploying to Kubernetes..."
./deploy.sh dev install

# Show status
kubectl get all -n yield-optimizer

echo ""
echo "Setup complete! Access your application:"
echo "kubectl port-forward -n yield-optimizer svc/yield-optimizer-monitor 8080:8080"
echo ""
echo "Then open: http://localhost:8080"
```

This approach is perfect for development because:
- No need for minikube VM overhead
- Uses your local Docker daemon
- Integrates well with Docker Desktop's dashboard
- Easy to switch between Docker Compose and Kubernetes
- Native port forwarding and LoadBalancer support