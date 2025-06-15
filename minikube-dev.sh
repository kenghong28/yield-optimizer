#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Yield Optimizer Minikube Development Setup ===${NC}"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"
for cmd in minikube kubectl helm docker; do
    if command_exists "$cmd"; then
        echo -e "${GREEN}✓${NC} $cmd is installed"
    else
        echo -e "${YELLOW}✗${NC} $cmd is not installed. Please install it first."
        exit 1
    fi
done
echo ""

# Start or configure minikube
echo -e "${BLUE}Setting up minikube...${NC}"
if minikube status >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Minikube is already running"
else
    echo "Starting minikube with recommended settings..."
    minikube start --cpus=4 --memory=8192 --disk-size=20g
fi

# Enable addons
echo -e "${BLUE}Enabling minikube addons...${NC}"
minikube addons enable ingress
minikube addons enable metrics-server
echo ""

# Configure Docker to use minikube
echo -e "${BLUE}Configuring Docker to use minikube...${NC}"
eval $(minikube docker-env)
echo -e "${GREEN}✓${NC} Docker is now using minikube's daemon"
echo ""

# Build Docker image
echo -e "${BLUE}Building Docker image...${NC}"
cd services/monitor
docker build -t yield-optimizer/monitor:dev .
cd ../..
echo -e "${GREEN}✓${NC} Docker image built successfully"
echo ""

# Create namespace
echo -e "${BLUE}Creating Kubernetes namespace...${NC}"
kubectl apply -f k8s/manifests/namespace.yaml
echo ""

# Check if secrets exist
echo -e "${BLUE}Checking secrets...${NC}"
if kubectl get secret yield-optimizer-db-secret -n yield-optimizer >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Database secret already exists"
else
    echo -e "${YELLOW}!${NC} Database secret not found"
    echo "Please create it with:"
    echo "kubectl create secret generic yield-optimizer-db-secret \\"
    echo "  -n yield-optimizer \\"
    echo "  --from-literal=database-url='your-supabase-url' \\"
    echo "  --from-literal=database-password='your-password'"
    echo ""
    echo "Using dummy secret for now..."
    kubectl create secret generic yield-optimizer-db-secret \
        -n yield-optimizer \
        --from-literal=database-url='postgresql://dummy:dummy@dummy:5432/dummy' \
        --from-literal=database-password='dummy-password' \
        --dry-run=client -o yaml | kubectl apply -f -
fi
echo ""

# Deploy application
echo -e "${BLUE}Deploying application...${NC}"
./deploy.sh dev install
echo ""

# Wait for deployment
echo -e "${BLUE}Waiting for pods to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=yield-optimizer -n yield-optimizer --timeout=300s
echo ""

# Show status
echo -e "${BLUE}Deployment Status:${NC}"
kubectl get all -n yield-optimizer
echo ""

# Port forwarding
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo "To access the application:"
echo "1. Port forward: kubectl port-forward -n yield-optimizer svc/yield-optimizer-monitor 8080:8080"
echo "2. Open browser: http://localhost:8080"
echo ""
echo "Other useful commands:"
echo "- View logs: kubectl logs -n yield-optimizer -l app.kubernetes.io/name=yield-optimizer -f"
echo "- Open dashboard: minikube dashboard"
echo "- Get service URL: minikube service yield-optimizer-monitor -n yield-optimizer --url"
echo "- SSH to minikube: minikube ssh"
echo ""
echo -e "${YELLOW}Starting port forward...${NC}"
echo "Press Ctrl+C to stop"
kubectl port-forward -n yield-optimizer svc/yield-optimizer-monitor 8080:8080