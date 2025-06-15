# Yield Optimizer - Minikube Development Deployment

Quick guide for deploying yield-optimizer to minikube for local development.

## Prerequisites

```bash
# Install minikube (macOS)
brew install minikube

# Install kubectl
brew install kubectl

# Install helm
brew install helm
```

## 1. Start Minikube

```bash
# Start minikube with sufficient resources
minikube start --cpus=4 --memory=8192 --disk-size=20g

# Enable required addons
minikube addons enable ingress
minikube addons enable metrics-server
minikube addons enable dashboard

# Verify minikube is running
minikube status
```

## 2. Use Minikube Docker Daemon

```bash
# Point your docker CLI to minikube's docker daemon
eval $(minikube docker-env)

# Verify - should show minikube's docker images
docker images

# Build image directly in minikube
cd services/monitor
docker build -t yield-optimizer/monitor:dev .
cd ../..
```

## 3. Quick Deploy

```bash
# Create namespace
kubectl apply -f k8s/manifests/namespace.yaml

# Create secrets (use test values for dev)
kubectl create secret generic yield-optimizer-db-secret \
  -n yield-optimizer \
  --from-literal=database-url='your-supabase-dev-url' \
  --from-literal=database-password='your-dev-password'

# Deploy with dev values
./deploy.sh dev install
```

## 4. Access Services

### Option 1: Port Forward (Recommended)
```bash
# Port forward to monitor service
kubectl port-forward -n yield-optimizer svc/yield-optimizer-monitor 8080:8080

# Access at http://localhost:8080
```

### Option 2: Minikube Service
```bash
# Open service in browser
minikube service yield-optimizer-monitor -n yield-optimizer

# Get service URL
minikube service yield-optimizer-monitor -n yield-optimizer --url
```

### Option 3: Ingress
```bash
# Get minikube IP
minikube ip

# Add to /etc/hosts
echo "$(minikube ip) yield-optimizer.local" | sudo tee -a /etc/hosts

# Access at http://yield-optimizer.local
```

## 5. Development Workflow

### Hot Reload Setup
```bash
# Keep using minikube docker
eval $(minikube docker-env)

# Rebuild and redeploy
cd services/monitor
docker build -t yield-optimizer/monitor:dev .
cd ../..

# Force pod restart
kubectl rollout restart deployment/yield-optimizer-monitor -n yield-optimizer
```

### View Logs
```bash
# Stream logs
kubectl logs -n yield-optimizer -l app.kubernetes.io/name=yield-optimizer -f

# Or use stern for better log viewing
brew install stern
stern -n yield-optimizer yield-optimizer
```

### Access Dashboard
```bash
# Open Kubernetes dashboard
minikube dashboard

# Navigate to yield-optimizer namespace
```

## 6. Useful Minikube Commands

```bash
# SSH into minikube VM
minikube ssh

# Check resource usage
minikube top

# Clean up everything
minikube delete

# Pause minikube (preserves state)
minikube pause

# Resume minikube
minikube unpause
```

## 7. Troubleshooting

### Image Pull Issues
```bash
# Since we build locally, ensure imagePullPolicy is set correctly
# In values-dev.yaml:
# monitor:
#   image:
#     pullPolicy: Never  # or IfNotPresent
```

### Resource Constraints
```bash
# Check minikube resources
kubectl top nodes
kubectl top pods -n yield-optimizer

# Increase resources if needed
minikube stop
minikube start --cpus=6 --memory=10240
```

### DNS Issues
```bash
# Test DNS from a pod
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
```

## 8. Development Tips

### 1. Use Tilt for Hot Reload (Optional)
```bash
# Install Tilt
brew install tilt-dev/tap/tilt

# Create Tiltfile (example)
cat > Tiltfile <<EOF
docker_build('yield-optimizer/monitor:dev', './services/monitor')
k8s_yaml(['k8s/manifests/namespace.yaml'])
k8s_yaml(helm('./helm/yield-optimizer', values=['./helm/yield-optimizer/values-dev.yaml']))
k8s_resource('yield-optimizer-monitor', port_forwards=8080)
EOF

# Run Tilt
tilt up
```

### 2. Local Development Mode
```bash
# Run monitor locally but connect to minikube services
kubectl port-forward -n yield-optimizer svc/yield-optimizer-redis 6379:6379 &

# Set environment variables
export REDIS_URL=localhost:6379
export SUPABASE_URL=your-supabase-url

# Run monitor locally
cd services/monitor
go run .
```

### 3. Cleanup
```bash
# Delete namespace (removes everything)
kubectl delete namespace yield-optimizer

# Or uninstall helm release
helm uninstall yield-optimizer -n yield-optimizer

# Stop minikube
minikube stop
```

## Quick Start Script

Create a `minikube-dev.sh`:

```bash
#!/bin/bash
set -e

echo "Starting minikube development environment..."

# Start minikube
minikube start --cpus=4 --memory=8192

# Use minikube docker
eval $(minikube docker-env)

# Build image
cd services/monitor
docker build -t yield-optimizer/monitor:dev .
cd ../..

# Deploy
kubectl apply -f k8s/manifests/namespace.yaml
./deploy.sh dev install

# Show status
kubectl get all -n yield-optimizer

# Port forward
echo "Starting port forward to http://localhost:8080"
kubectl port-forward -n yield-optimizer svc/yield-optimizer-monitor 8080:8080
```

Make it executable: `chmod +x minikube-dev.sh`
Run: `./minikube-dev.sh`