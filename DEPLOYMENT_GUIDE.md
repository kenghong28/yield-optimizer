# Yield Optimizer Kubernetes Deployment Guide

This guide provides step-by-step instructions for deploying the Yield Optimizer to a Kubernetes cluster.

## Prerequisites

### 1. Tools Required
- **kubectl**: Kubernetes command-line tool (v1.28+)
- **helm**: Kubernetes package manager (v3.13+)
- **docker**: Container runtime (v24.0+)
- **git**: Version control system

### 2. Cluster Access
- Access to a Kubernetes cluster (EKS, GKE, AKS, or local)
- Cluster admin permissions for initial setup
- Valid kubeconfig file configured

### 3. Container Registry
- Access to a container registry (Docker Hub, ECR, GCR, ACR)
- Registry credentials configured

## Pre-Deployment Steps

### 1. Verify Cluster Access
```bash
# Check kubectl configuration
kubectl config current-context

# Verify cluster connection
kubectl cluster-info

# Check available nodes
kubectl get nodes

# Verify Helm installation
helm version
```

### 2. Clone Repository
```bash
git clone <repository-url>
cd yield-optimizer
```

### 3. Review Configuration
```bash
# Review base values
cat helm/yield-optimizer/values.yaml

# Review environment-specific values
cat helm/yield-optimizer/values-dev.yaml
cat helm/yield-optimizer/values-prod.yaml
```

## Container Image Preparation

### 1. Configure Registry
```bash
# Set your registry URL
export REGISTRY_URL="your-registry.com"
export IMAGE_TAG="v1.0.0"

# Login to registry (example for Docker Hub)
docker login $REGISTRY_URL
```

### 2. Build and Push Images
```bash
# Build monitor service
cd services/monitor
docker build -t $REGISTRY_URL/yield-optimizer/monitor:$IMAGE_TAG .
docker push $REGISTRY_URL/yield-optimizer/monitor:$IMAGE_TAG
cd ../..
```

### 3. Update Helm Values
```bash
# Update the image repository in values files
# Edit helm/yield-optimizer/values-dev.yaml or values-prod.yaml
# Set monitor.image.repository and monitor.image.tag
```

## Database Setup

### 1. Supabase Configuration
Since we're using external Supabase for PostgreSQL:

```bash
# Obtain from Supabase dashboard:
# - Database URL
# - Database password
# - Connection string

# These will be used in the next steps
```

### 2. Create Kubernetes Secrets
```bash
# Create database secret
kubectl create secret generic yield-optimizer-db-secret \
  --namespace yield-optimizer \
  --from-literal=database-url='postgresql://user:password@host:5432/dbname' \
  --from-literal=database-password='your-password'

# Create Redis secret (if using authentication)
kubectl create secret generic yield-optimizer-redis-secret \
  --namespace yield-optimizer \
  --from-literal=redis-password='your-redis-password'
```

## Deployment Steps

### 1. Deploy to Development Environment

```bash
# Navigate to project root
cd /path/to/yield-optimizer

# Deploy using the deployment script
./deploy.sh dev install

# Or manually with Helm
helm install yield-optimizer ./helm/yield-optimizer \
  --namespace yield-optimizer \
  --create-namespace \
  --values ./helm/yield-optimizer/values-dev.yaml \
  --wait
```

### 2. Verify Deployment

```bash
# Check deployment status
./deploy.sh dev status

# Or manually check resources
kubectl get all -n yield-optimizer

# Check pod logs
kubectl logs -n yield-optimizer -l app.kubernetes.io/name=yield-optimizer -f

# Check service endpoints
kubectl get endpoints -n yield-optimizer
```

### 3. Test Connectivity

```bash
# Port forward to test locally
kubectl port-forward -n yield-optimizer service/yield-optimizer-monitor 8080:8080

# In another terminal, test the service
curl http://localhost:8080/health
curl http://localhost:8080/metrics
```

## Production Deployment

### 1. Pre-Production Checklist

- [ ] Update production values file with correct configuration
- [ ] Ensure production database credentials are set
- [ ] Configure proper resource limits and requests
- [ ] Set up monitoring endpoints
- [ ] Configure ingress with TLS/SSL
- [ ] Review security contexts and policies
- [ ] Test backup and restore procedures

### 2. Deploy to Production

```bash
# Deploy to production
./deploy.sh prod install

# Monitor rollout
kubectl rollout status deployment/yield-optimizer-monitor -n yield-optimizer

# Check production pods
kubectl get pods -n yield-optimizer -l environment=production
```

### 3. Configure Ingress

```bash
# Apply TLS certificate (example with cert-manager)
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: yield-optimizer-tls
  namespace: yield-optimizer
spec:
  secretName: yield-optimizer-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - yield-optimizer.yourdomain.com
EOF

# Verify ingress
kubectl get ingress -n yield-optimizer
kubectl describe ingress yield-optimizer -n yield-optimizer
```

## Post-Deployment Tasks

### 1. Configure Monitoring

```bash
# Check Prometheus ServiceMonitor
kubectl get servicemonitor -n yield-optimizer

# Verify metrics endpoint
curl http://yield-optimizer.yourdomain.com/metrics

# Configure Grafana dashboards (if applicable)
```

### 2. Set Up Alerts

```bash
# Apply PrometheusRule for alerts
kubectl apply -f k8s/monitoring/prometheus-rules.yaml

# Verify alerts
kubectl get prometheusrule -n yield-optimizer
```

### 3. Configure Autoscaling

```bash
# Check HPA status
kubectl get hpa -n yield-optimizer

# Monitor scaling events
kubectl describe hpa yield-optimizer-monitor -n yield-optimizer

# Test scaling
kubectl run -i --tty load-generator --rm --image=busybox --restart=Never -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://yield-optimizer-monitor.yield-optimizer.svc.cluster.local:8080; done"
```

## Troubleshooting

### Common Issues

#### 1. Pods Not Starting
```bash
# Check pod status
kubectl describe pod <pod-name> -n yield-optimizer

# Check events
kubectl get events -n yield-optimizer --sort-by='.lastTimestamp'

# Check resource quotas
kubectl describe resourcequota -n yield-optimizer
```

#### 2. Database Connection Issues
```bash
# Verify secret exists
kubectl get secret yield-optimizer-db-secret -n yield-optimizer

# Check secret content (base64 encoded)
kubectl get secret yield-optimizer-db-secret -n yield-optimizer -o yaml

# Test connection from pod
kubectl exec -it <pod-name> -n yield-optimizer -- /bin/sh
# Then test connection with psql or your app's connection test
```

#### 3. Service Not Accessible
```bash
# Check service endpoints
kubectl get endpoints yield-optimizer-monitor -n yield-optimizer

# Check service selector
kubectl describe service yield-optimizer-monitor -n yield-optimizer

# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup yield-optimizer-monitor.yield-optimizer.svc.cluster.local
```

### Rollback Procedure

```bash
# List helm releases
helm list -n yield-optimizer

# Check release history
helm history yield-optimizer -n yield-optimizer

# Rollback to previous version
helm rollback yield-optimizer <revision-number> -n yield-optimizer

# Verify rollback
kubectl get pods -n yield-optimizer
helm status yield-optimizer -n yield-optimizer
```

## Maintenance Operations

### 1. Updating Configuration

```bash
# Update values and upgrade
helm upgrade yield-optimizer ./helm/yield-optimizer \
  --namespace yield-optimizer \
  --values ./helm/yield-optimizer/values-prod.yaml

# Watch the rollout
kubectl rollout status deployment/yield-optimizer-monitor -n yield-optimizer
```

### 2. Scaling Operations

```bash
# Manual scaling
kubectl scale deployment yield-optimizer-monitor --replicas=5 -n yield-optimizer

# Update HPA limits
kubectl edit hpa yield-optimizer-monitor -n yield-optimizer
```

### 3. Log Collection

```bash
# View logs for all pods
kubectl logs -n yield-optimizer -l app.kubernetes.io/name=yield-optimizer --tail=100

# Export logs
kubectl logs -n yield-optimizer -l app.kubernetes.io/name=yield-optimizer > yield-optimizer-logs.txt

# Stream logs
kubectl logs -n yield-optimizer -l app.kubernetes.io/name=yield-optimizer -f
```

## Security Considerations

### 1. RBAC Configuration
```bash
# Review service account permissions
kubectl describe serviceaccount yield-optimizer -n yield-optimizer
kubectl describe clusterrole yield-optimizer
kubectl describe clusterrolebinding yield-optimizer
```

### 2. Network Policies
```bash
# Apply network policies (create these based on your security requirements)
kubectl apply -f k8s/security/network-policies.yaml

# Verify policies
kubectl get networkpolicy -n yield-optimizer
```

### 3. Secret Rotation
```bash
# Update secrets
kubectl create secret generic yield-optimizer-db-secret \
  --namespace yield-optimizer \
  --from-literal=database-url='new-connection-string' \
  --from-literal=database-password='new-password' \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods to pick up new secrets
kubectl rollout restart deployment/yield-optimizer-monitor -n yield-optimizer
```

## Monitoring and Observability

### 1. Health Checks
```bash
# Check liveness probe
curl http://yield-optimizer.yourdomain.com/health/live

# Check readiness probe
curl http://yield-optimizer.yourdomain.com/health/ready
```

### 2. Metrics Collection
```bash
# View Prometheus metrics
curl http://yield-optimizer.yourdomain.com/metrics

# Key metrics to monitor:
# - yield_optimizer_positions_total
# - yield_optimizer_apy_current
# - yield_optimizer_errors_total
# - http_request_duration_seconds
```

### 3. Dashboard Access
- Grafana: Configure dashboards for yield optimizer metrics
- Prometheus: Set up recording rules and alerts
- Kubernetes Dashboard: Monitor resource usage

## Cleanup

### Remove Deployment
```bash
# Uninstall using script
./deploy.sh dev uninstall

# Or manually with Helm
helm uninstall yield-optimizer -n yield-optimizer

# Remove namespace (this removes all resources)
kubectl delete namespace yield-optimizer

# Remove persistent volumes (if any remain)
kubectl delete pv -l app.kubernetes.io/name=yield-optimizer
```

## Next Steps

1. Set up CI/CD pipeline for automated deployments
2. Configure backup and disaster recovery procedures
3. Implement advanced monitoring with custom dashboards
4. Set up log aggregation with ELK or similar stack
5. Configure cost optimization and resource management

## Support

For issues or questions:
1. Check pod logs and events
2. Review Helm release notes
3. Consult Kubernetes documentation
4. Contact the development team