#!/bin/bash

# Yield Optimizer Kubernetes Deployment Script
set -e

# Configuration
NAMESPACE="yield-optimizer"
CHART_PATH="./helm/yield-optimizer"
RELEASE_NAME="yield-optimizer"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    echo "Usage: $0 [ENVIRONMENT] [COMMAND]"
    echo ""
    echo "Environments:"
    echo "  dev     Deploy to development environment"
    echo "  prod    Deploy to production environment"
    echo ""
    echo "Commands:"
    echo "  install    Install the Helm chart"
    echo "  upgrade    Upgrade existing deployment"
    echo "  uninstall  Remove the deployment"
    echo "  status     Show deployment status"
    echo "  logs       Show pod logs"
    echo "  port-forward  Port forward to monitor service"
    echo ""
    echo "Examples:"
    echo "  $0 dev install"
    echo "  $0 prod upgrade"
    echo "  $0 dev status"
    echo "  $0 dev logs"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed or not in PATH"
        exit 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Create namespace if it doesn't exist
create_namespace() {
    log_info "Creating namespace if not exists..."
    kubectl apply -f k8s/manifests/namespace.yaml
    log_success "Namespace ready"
}

# Build and push Docker image (optional)
build_image() {
    local env=$1
    log_info "Building Docker image for $env environment..."
    
    # Build monitor service image
    cd services/monitor
    docker build -t yield-optimizer/monitor:$env .
    cd ../..
    
    # If using a registry, push the image
    # docker push yield-optimizer/monitor:$env
    
    log_success "Docker image built"
}

# Install Helm chart
install_chart() {
    local env=$1
    local values_file="values-${env}.yaml"
    
    log_info "Installing Helm chart for $env environment..."
    
    # Validate chart
    helm lint $CHART_PATH
    
    # Install chart
    helm install $RELEASE_NAME $CHART_PATH \
        --namespace $NAMESPACE \
        --create-namespace \
        --values $CHART_PATH/$values_file \
        --wait \
        --timeout 300s
        
    log_success "Helm chart installed successfully"
}

# Upgrade Helm chart
upgrade_chart() {
    local env=$1
    local values_file="values-${env}.yaml"
    
    log_info "Upgrading Helm chart for $env environment..."
    
    # Validate chart
    helm lint $CHART_PATH
    
    # Upgrade chart
    helm upgrade $RELEASE_NAME $CHART_PATH \
        --namespace $NAMESPACE \
        --values $CHART_PATH/$values_file \
        --wait \
        --timeout 300s
        
    log_success "Helm chart upgraded successfully"
}

# Uninstall Helm chart
uninstall_chart() {
    log_info "Uninstalling Helm chart..."
    
    helm uninstall $RELEASE_NAME --namespace $NAMESPACE
    
    log_success "Helm chart uninstalled"
}

# Show deployment status
show_status() {
    log_info "Deployment status:"
    
    echo ""
    echo "Helm releases:"
    helm list --namespace $NAMESPACE
    
    echo ""
    echo "Pods:"
    kubectl get pods --namespace $NAMESPACE
    
    echo ""
    echo "Services:"
    kubectl get services --namespace $NAMESPACE
    
    echo ""
    echo "Ingress:"
    kubectl get ingress --namespace $NAMESPACE
}

# Show logs
show_logs() {
    log_info "Showing pod logs..."
    
    # Get monitor pod name
    MONITOR_POD=$(kubectl get pods --namespace $NAMESPACE -l app.kubernetes.io/component=monitor -o jsonpath='{.items[0].metadata.name}')
    
    if [ -n "$MONITOR_POD" ]; then
        kubectl logs --namespace $NAMESPACE $MONITOR_POD --follow
    else
        log_error "No monitor pod found"
    fi
}

# Port forward to monitor service
port_forward() {
    log_info "Port forwarding to monitor service..."
    
    kubectl port-forward --namespace $NAMESPACE service/${RELEASE_NAME}-monitor 8080:8080
}

# Main execution
ENV=${1:-dev}
COMMAND=${2:-install}

case $ENV in
    dev|prod)
        ;;
    *)
        log_error "Invalid environment: $ENV"
        show_help
        exit 1
        ;;
esac

case $COMMAND in
    install)
        check_prerequisites
        create_namespace
        install_chart $ENV
        show_status
        ;;
    upgrade)
        check_prerequisites
        upgrade_chart $ENV
        show_status
        ;;
    uninstall)
        check_prerequisites
        uninstall_chart
        ;;
    status)
        check_prerequisites
        show_status
        ;;
    logs)
        check_prerequisites
        show_logs
        ;;
    port-forward)
        check_prerequisites
        port_forward
        ;;
    build)
        build_image $ENV
        ;;
    *)
        log_error "Invalid command: $COMMAND"
        show_help
        exit 1
        ;;
esac