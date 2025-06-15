#!/bin/bash

# Pre-deployment validation script
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Yield Optimizer Pre-Deployment Check ==="
echo ""

# Track overall status
CHECKS_PASSED=true

# Function to check command availability
check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is installed: $(command -v $1)"
        return 0
    else
        echo -e "${RED}✗${NC} $1 is not installed"
        CHECKS_PASSED=false
        return 1
    fi
}

# Function to check version
check_version() {
    local cmd=$1
    local version_flag=$2
    local min_version=$3
    
    if command -v $cmd &> /dev/null; then
        version=$($cmd $version_flag 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
        echo -e "${GREEN}✓${NC} $cmd version: $version (minimum: $min_version)"
    fi
}

# 1. Check Required Tools
echo "1. Checking required tools..."
check_command kubectl
check_command helm
check_command docker
check_command git

echo ""

# 2. Check Versions
echo "2. Checking tool versions..."
check_version kubectl "version --client --short" "1.28"
check_version helm "version --short" "3.13"
check_version docker "--version" "24.0"

echo ""

# 3. Check Kubernetes Connectivity
echo "3. Checking Kubernetes cluster connectivity..."
if kubectl cluster-info &> /dev/null; then
    echo -e "${GREEN}✓${NC} Connected to cluster: $(kubectl config current-context)"
    
    # Check nodes
    node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    if [ $node_count -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Cluster has $node_count nodes"
    else
        echo -e "${RED}✗${NC} No nodes found in cluster"
        CHECKS_PASSED=false
    fi
else
    echo -e "${RED}✗${NC} Cannot connect to Kubernetes cluster"
    echo -e "${YELLOW}!${NC} Run: kubectl config view"
    CHECKS_PASSED=false
fi

echo ""

# 4. Check Namespace
echo "4. Checking namespace..."
if kubectl get namespace yield-optimizer &> /dev/null; then
    echo -e "${GREEN}✓${NC} Namespace 'yield-optimizer' exists"
else
    echo -e "${YELLOW}!${NC} Namespace 'yield-optimizer' does not exist (will be created)"
fi

echo ""

# 5. Check Helm Chart
echo "5. Validating Helm chart..."
CHART_PATH="./helm/yield-optimizer"
if [ -d "$CHART_PATH" ]; then
    echo -e "${GREEN}✓${NC} Helm chart directory found"
    
    # Lint the chart
    if helm lint $CHART_PATH &> /dev/null; then
        echo -e "${GREEN}✓${NC} Helm chart validation passed"
    else
        echo -e "${RED}✗${NC} Helm chart validation failed"
        helm lint $CHART_PATH
        CHECKS_PASSED=false
    fi
    
    # Check required values files
    for env in dev prod; do
        if [ -f "$CHART_PATH/values-${env}.yaml" ]; then
            echo -e "${GREEN}✓${NC} Found values-${env}.yaml"
        else
            echo -e "${RED}✗${NC} Missing values-${env}.yaml"
            CHECKS_PASSED=false
        fi
    done
else
    echo -e "${RED}✗${NC} Helm chart directory not found at $CHART_PATH"
    CHECKS_PASSED=false
fi

echo ""

# 6. Check Docker Registry Access
echo "6. Checking Docker registry access..."
if docker info &> /dev/null; then
    echo -e "${GREEN}✓${NC} Docker daemon is running"
    
    # Check if logged in to any registry
    if docker info 2>/dev/null | grep -q "Username"; then
        echo -e "${GREEN}✓${NC} Logged in to Docker registry"
    else
        echo -e "${YELLOW}!${NC} Not logged in to any Docker registry"
        echo -e "${YELLOW}!${NC} Run: docker login <your-registry>"
    fi
else
    echo -e "${RED}✗${NC} Docker daemon is not running"
    CHECKS_PASSED=false
fi

echo ""

# 7. Check Required Secrets
echo "7. Checking Kubernetes secrets..."
if kubectl get namespace yield-optimizer &> /dev/null; then
    if kubectl get secret yield-optimizer-db-secret -n yield-optimizer &> /dev/null; then
        echo -e "${GREEN}✓${NC} Database secret exists"
    else
        echo -e "${YELLOW}!${NC} Database secret not found (needs to be created)"
        echo -e "${YELLOW}!${NC} Run: kubectl create secret generic yield-optimizer-db-secret -n yield-optimizer --from-literal=database-url='...' --from-literal=database-password='...'"
    fi
else
    echo -e "${YELLOW}!${NC} Namespace doesn't exist yet, skipping secret check"
fi

echo ""

# 8. Check Available Resources
echo "8. Checking cluster resources..."
if kubectl top nodes &> /dev/null; then
    echo -e "${GREEN}✓${NC} Metrics server is available"
    echo "Node resources:"
    kubectl top nodes | head -5
else
    echo -e "${YELLOW}!${NC} Metrics server not available (optional but recommended)"
fi

echo ""

# 9. Check Storage Classes
echo "9. Checking storage classes..."
storage_classes=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l)
if [ $storage_classes -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Found $storage_classes storage classes"
    kubectl get storageclass
else
    echo -e "${YELLOW}!${NC} No storage classes found (required for persistent volumes)"
fi

echo ""

# 10. Final Summary
echo "=== Pre-Deployment Check Summary ==="
if [ "$CHECKS_PASSED" = true ]; then
    echo -e "${GREEN}✓ All critical checks passed!${NC}"
    echo ""
    echo "You can proceed with deployment:"
    echo "  ./deploy.sh dev install    # For development"
    echo "  ./deploy.sh prod install   # For production"
else
    echo -e "${RED}✗ Some checks failed!${NC}"
    echo ""
    echo "Please fix the issues above before proceeding with deployment."
    exit 1
fi

echo ""
echo "Optional: Run './k8s/scripts/validate-config.sh <env>' to validate environment configuration"