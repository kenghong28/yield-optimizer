#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Yield Optimizer Docker Desktop Development Setup ===${NC}"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"
for cmd in kubectl helm docker; do
    if command_exists "$cmd"; then
        echo -e "${GREEN}✓${NC} $cmd is installed"
    else
        echo -e "${RED}✗${NC} $cmd is not installed. Please install it first."
        exit 1
    fi
done
echo ""

# Check if Docker Desktop Kubernetes is enabled
echo -e "${BLUE}Checking Docker Desktop Kubernetes...${NC}"
if kubectl config current-context 2>/dev/null | grep -q "docker-desktop"; then
    echo -e "${GREEN}✓${NC} Docker Desktop Kubernetes context is active"
else
    echo -e "${RED}✗${NC} Docker Desktop Kubernetes is not enabled or not current context"
    echo "Please:"
    echo "1. Open Docker Desktop"
    echo "2. Go to Settings → Kubernetes"
    echo "3. Enable Kubernetes"
    echo "4. Run: kubectl config use-context docker-desktop"
    exit 1
fi

# Verify cluster connectivity
if kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Kubernetes cluster is accessible"
else
    echo -e "${RED}✗${NC} Cannot connect to Kubernetes cluster"
    exit 1
fi
echo ""

# Check Docker daemon
echo -e "${BLUE}Checking Docker daemon...${NC}"
if docker info >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Docker daemon is running"
else
    echo -e "${RED}✗${NC} Docker daemon is not running. Please start Docker Desktop."
    exit 1
fi
echo ""

# Build Docker image
echo -e "${BLUE}Building Docker image...${NC}"
if [ -d "services/monitor" ]; then
    cd services/monitor
    echo "Building yield-optimizer/monitor:dev..."
    docker build -t yield-optimizer/monitor:dev .
    cd ../..
    echo -e "${GREEN}✓${NC} Docker image built successfully"
else
    echo -e "${RED}✗${NC} services/monitor directory not found"
    exit 1
fi
echo ""

# Update values-dev.yaml to use local image
echo -e "${BLUE}Updating values-dev.yaml for local development...${NC}"
VALUES_FILE="helm/yield-optimizer/values-dev.yaml"
if [ -f "$VALUES_FILE" ]; then
    # Create backup
    cp "$VALUES_FILE" "${VALUES_FILE}.backup"
    
    # Update image settings for local development
    if grep -q "pullPolicy:" "$VALUES_FILE"; then
        sed -i '' 's/pullPolicy:.*/pullPolicy: Never/' "$VALUES_FILE"
    else
        # Add pullPolicy if it doesn't exist
        sed -i '' '/image:/a\
    pullPolicy: Never' "$VALUES_FILE"
    fi
    
    echo -e "${GREEN}✓${NC} Updated values-dev.yaml for local images"
else
    echo -e "${YELLOW}!${NC} values-dev.yaml not found, using defaults"
fi
echo ""

# Create namespace
echo -e "${BLUE}Creating Kubernetes namespace...${NC}"
if [ -f "k8s/manifests/namespace.yaml" ]; then
    kubectl apply -f k8s/manifests/namespace.yaml
    echo -e "${GREEN}✓${NC} Namespace created/updated"
else
    echo -e "${YELLOW}!${NC} Namespace manifest not found, creating namespace manually"
    kubectl create namespace yield-optimizer --dry-run=client -o yaml | kubectl apply -f -
fi
echo ""

# Check if secrets exist
echo -e "${BLUE}Checking secrets...${NC}"
if kubectl get secret yield-optimizer-db-secret -n yield-optimizer >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Database secret already exists"
else
    echo -e "${YELLOW}!${NC} Database secret not found"
    read -p "Do you want to create a dummy secret for development? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl create secret generic yield-optimizer-db-secret \
            -n yield-optimizer \
            --from-literal=database-url='postgresql://dummy:dummy@dummy:5432/dummy' \
            --from-literal=database-password='dummy-password'
        echo -e "${GREEN}✓${NC} Created dummy database secret"
    else
        echo "Please create the secret manually:"
        echo "kubectl create secret generic yield-optimizer-db-secret \\"
        echo "  -n yield-optimizer \\"
        echo "  --from-literal=database-url='your-supabase-url' \\"
        echo "  --from-literal=database-password='your-password'"
        exit 1
    fi
fi
echo ""

# Deploy application
echo -e "${BLUE}Deploying application...${NC}"
if [ -f "deploy.sh" ]; then
    chmod +x deploy.sh
    ./deploy.sh dev install
else
    echo -e "${YELLOW}!${NC} deploy.sh not found, deploying manually with helm"
    helm install yield-optimizer ./helm/yield-optimizer \
        --namespace yield-optimizer \
        --values ./helm/yield-optimizer/values-dev.yaml \
        --wait
fi
echo ""

# Wait for deployment
echo -e "${BLUE}Waiting for pods to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=yield-optimizer -n yield-optimizer --timeout=300s || {
    echo -e "${RED}✗${NC} Pods did not become ready in time"
    echo "Checking pod status:"
    kubectl get pods -n yield-optimizer
    echo ""
    echo "Pod descriptions:"
    kubectl describe pods -n yield-optimizer
    exit 1
}
echo ""

# Show status
echo -e "${BLUE}Deployment Status:${NC}"
kubectl get all -n yield-optimizer
echo ""

# Check if service is accessible
echo -e "${BLUE}Testing service accessibility...${NC}"
SERVICE_NAME=$(kubectl get svc -n yield-optimizer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$SERVICE_NAME" ]; then
    echo -e "${GREEN}✓${NC} Service $SERVICE_NAME is available"
else
    echo -e "${YELLOW}!${NC} No services found"
fi
echo ""

# Create convenience scripts
echo -e "${BLUE}Creating convenience scripts...${NC}"

# Create reload script
cat > dev-reload.sh << 'EOF'
#!/bin/bash
echo "=== Rebuilding and Redeploying ==="
cd services/monitor
docker build -t yield-optimizer/monitor:dev .
cd ../..
kubectl rollout restart deployment/yield-optimizer-monitor -n yield-optimizer
echo "Waiting for rollout to complete..."
kubectl rollout status deployment/yield-optimizer-monitor -n yield-optimizer
echo "Deployment ready!"
EOF
chmod +x dev-reload.sh

# Create logs script
cat > dev-logs.sh << 'EOF'
#!/bin/bash
echo "=== Streaming Application Logs ==="
kubectl logs -n yield-optimizer -l app.kubernetes.io/name=yield-optimizer -f
EOF
chmod +x dev-logs.sh

# Create cleanup script
cat > dev-cleanup.sh << 'EOF'
#!/bin/bash
echo "=== Cleaning Up Development Environment ==="
helm uninstall yield-optimizer -n yield-optimizer 2>/dev/null || true
kubectl delete namespace yield-optimizer 2>/dev/null || true
docker rmi yield-optimizer/monitor:dev 2>/dev/null || true
echo "Cleanup complete!"
EOF
chmod +x dev-cleanup.sh

echo -e "${GREEN}✓${NC} Created convenience scripts:"
echo "  - dev-reload.sh: Rebuild and redeploy"
echo "  - dev-logs.sh: Stream application logs"
echo "  - dev-cleanup.sh: Clean up everything"
echo ""

# Final success message
echo -e "${GREEN}=== Setup Complete! ===${NC}"
echo ""
echo "Your yield-optimizer is now running in Docker Desktop Kubernetes!"
echo ""
echo -e "${BLUE}Access your application:${NC}"
echo "1. Port forward: kubectl port-forward -n yield-optimizer svc/$SERVICE_NAME 8080:8080"
echo "2. Open browser: http://localhost:8080"
echo ""
echo -e "${BLUE}Development commands:${NC}"
echo "- View logs: ./dev-logs.sh"
echo "- Rebuild & redeploy: ./dev-reload.sh"
echo "- View status: kubectl get all -n yield-optimizer"
echo "- Clean up: ./dev-cleanup.sh"
echo ""
echo -e "${BLUE}Docker Desktop dashboard:${NC}"
echo "- Open Docker Desktop and go to Kubernetes tab"
echo "- Browse yield-optimizer namespace"
echo ""

# Offer to start port forwarding
echo -e "${YELLOW}Would you like to start port forwarding now? (y/n)${NC}"
read -p "> " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Starting port forward to http://localhost:8080${NC}"
    echo "Press Ctrl+C to stop"
    kubectl port-forward -n yield-optimizer svc/$SERVICE_NAME 8080:8080
fi