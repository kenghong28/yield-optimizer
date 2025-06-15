#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Yield Optimizer Monitoring Deployment ===${NC}"
echo ""

# Configuration
MONITORING_NAMESPACE="monitoring"
YIELD_NAMESPACE="yield-optimizer"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"
if ! command_exists helm; then
    echo -e "${RED}✗${NC} Helm is not installed"
    exit 1
fi

if ! command_exists kubectl; then
    echo -e "${RED}✗${NC} kubectl is not installed"
    exit 1
fi

echo -e "${GREEN}✓${NC} Prerequisites met"
echo ""

# Add Prometheus Helm repository
echo -e "${BLUE}Adding Prometheus Helm repository...${NC}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
echo -e "${GREEN}✓${NC} Helm repositories updated"
echo ""

# Create monitoring namespace
echo -e "${BLUE}Creating monitoring namespace...${NC}"
kubectl create namespace $MONITORING_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓${NC} Monitoring namespace ready"
echo ""

# Install kube-prometheus-stack
echo -e "${BLUE}Installing Prometheus stack...${NC}"
if helm list -n $MONITORING_NAMESPACE | grep -q prometheus-stack; then
    echo -e "${YELLOW}!${NC} Prometheus stack already installed, upgrading..."
    helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace $MONITORING_NAMESPACE \
        --values k8s/monitoring/kube-prometheus-stack-values.yaml \
        --wait
else
    echo "Installing fresh Prometheus stack..."
    helm install prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace $MONITORING_NAMESPACE \
        --values k8s/monitoring/kube-prometheus-stack-values.yaml \
        --wait \
        --timeout 10m
fi
echo -e "${GREEN}✓${NC} Prometheus stack installed"
echo ""

# Apply monitoring resources
echo -e "${BLUE}Applying monitoring resources...${NC}"

# Apply PrometheusRule
if [ -f "k8s/monitoring/prometheus-rules.yaml" ]; then
    kubectl apply -f k8s/monitoring/prometheus-rules.yaml
    echo -e "${GREEN}✓${NC} Prometheus rules applied"
else
    echo -e "${YELLOW}!${NC} Prometheus rules file not found"
fi

# Apply Grafana dashboard ConfigMap
if [ -f "k8s/monitoring/grafana-dashboard-configmap.yaml" ]; then
    kubectl apply -f k8s/monitoring/grafana-dashboard-configmap.yaml
    echo -e "${GREEN}✓${NC} Grafana dashboard ConfigMap applied"
else
    echo -e "${YELLOW}!${NC} Grafana dashboard ConfigMap not found"
fi
echo ""

# Wait for deployments
echo -e "${BLUE}Waiting for monitoring stack to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n $MONITORING_NAMESPACE --timeout=300s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n $MONITORING_NAMESPACE --timeout=300s
echo -e "${GREEN}✓${NC} Monitoring stack is ready"
echo ""

# Get Grafana admin password
echo -e "${BLUE}Retrieving Grafana credentials...${NC}"
GRAFANA_PASSWORD=$(kubectl get secret --namespace $MONITORING_NAMESPACE prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
echo -e "${GREEN}✓${NC} Grafana admin password: ${YELLOW}$GRAFANA_PASSWORD${NC}"
echo ""

# Create monitoring scripts
echo -e "${BLUE}Creating monitoring access scripts...${NC}"

# Create Prometheus access script
cat > prometheus-access.sh << 'EOF'
#!/bin/bash
echo "Starting Prometheus port-forward..."
echo "Access Prometheus at: http://localhost:9090"
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090
EOF
chmod +x prometheus-access.sh

# Create Grafana access script
cat > grafana-access.sh << EOF
#!/bin/bash
echo "Starting Grafana port-forward..."
echo "Access Grafana at: http://localhost:3000"
echo "Username: admin"
echo "Password: $GRAFANA_PASSWORD"
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
EOF
chmod +x grafana-access.sh

# Create AlertManager access script
cat > alertmanager-access.sh << 'EOF'
#!/bin/bash
echo "Starting AlertManager port-forward..."
echo "Access AlertManager at: http://localhost:9093"
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-alertmanager 9093:9093
EOF
chmod +x alertmanager-access.sh

echo -e "${GREEN}✓${NC} Created access scripts:"
echo "  - ./prometheus-access.sh"
echo "  - ./grafana-access.sh"
echo "  - ./alertmanager-access.sh"
echo ""

# Show monitoring status
echo -e "${BLUE}Monitoring Stack Status:${NC}"
echo ""
echo "Prometheus:"
kubectl get svc -n $MONITORING_NAMESPACE | grep prometheus | grep -v operator
echo ""
echo "Grafana:"
kubectl get svc -n $MONITORING_NAMESPACE | grep grafana
echo ""
echo "AlertManager:"
kubectl get svc -n $MONITORING_NAMESPACE | grep alertmanager
echo ""

# Check if yield-optimizer is deployed
if kubectl get namespace $YIELD_NAMESPACE >/dev/null 2>&1; then
    echo -e "${BLUE}Checking yield-optimizer ServiceMonitor...${NC}"
    if kubectl get servicemonitor -n $YIELD_NAMESPACE >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} ServiceMonitor found in yield-optimizer namespace"
    else
        echo -e "${YELLOW}!${NC} No ServiceMonitor found. Make sure to deploy yield-optimizer with monitoring enabled"
    fi
else
    echo -e "${YELLOW}!${NC} Yield-optimizer namespace not found. Deploy the application first."
fi
echo ""

# Final instructions
echo -e "${GREEN}=== Monitoring Setup Complete ===${NC}"
echo ""
echo -e "${BLUE}Access the monitoring stack:${NC}"
echo "1. Prometheus: ./prometheus-access.sh"
echo "2. Grafana: ./grafana-access.sh"
echo "3. AlertManager: ./alertmanager-access.sh"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Access Grafana and import the Yield Optimizer dashboard"
echo "2. Configure alert notification channels in AlertManager"
echo "3. Deploy yield-optimizer with ServiceMonitor enabled"
echo "4. Verify metrics are being collected in Prometheus"
echo ""
echo -e "${YELLOW}Note:${NC} Make sure your yield-optimizer deployment includes:"
echo "- ServiceMonitor resource"
echo "- Metrics endpoint exposed on /metrics"
echo "- Proper labels for Prometheus discovery"