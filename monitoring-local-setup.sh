#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Yield Optimizer Local Monitoring Setup ===${NC}"
echo ""

# Check current context
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
echo -e "${BLUE}Current Kubernetes context:${NC} $CURRENT_CONTEXT"
echo ""

# Check if we can connect to the cluster
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}✗ Cannot connect to Kubernetes cluster${NC}"
    echo ""
    echo -e "${YELLOW}Options to proceed:${NC}"
    echo ""
    echo "1. ${BLUE}Enable Docker Desktop Kubernetes:${NC}"
    echo "   - Open Docker Desktop"
    echo "   - Go to Settings → Kubernetes"
    echo "   - Check 'Enable Kubernetes'"
    echo "   - Click 'Apply & Restart'"
    echo "   - Run: kubectl config use-context docker-desktop"
    echo ""
    echo "2. ${BLUE}Use DigitalOcean cluster:${NC}"
    echo "   - Authenticate with: doctl auth init"
    echo "   - Save kubeconfig: doctl kubernetes cluster kubeconfig save <cluster-name>"
    echo ""
    echo "3. ${BLUE}Use local Docker Compose alternative:${NC}"
    echo "   - See: docker-compose-monitoring.yaml"
    exit 1
fi

# Offer local Docker Compose alternative
echo -e "${BLUE}Creating Docker Compose monitoring alternative...${NC}"
cat > docker-compose-monitoring.yaml << 'EOF'
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: yield-optimizer-prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus-config.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:latest
    container_name: yield-optimizer-grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana-provisioning:/etc/grafana/provisioning
    networks:
      - monitoring
    depends_on:
      - prometheus

  alertmanager:
    image: prom/alertmanager:latest
    container_name: yield-optimizer-alertmanager
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager-config.yml:/etc/alertmanager/alertmanager.yml
      - alertmanager-data:/alertmanager
    networks:
      - monitoring

volumes:
  prometheus-data:
  grafana-data:
  alertmanager-data:

networks:
  monitoring:
    driver: bridge
EOF

# Create Prometheus config
cat > prometheus-config.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

rule_files:
  - "alerts.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'yield-optimizer'
    static_configs:
      - targets: ['host.docker.internal:8080']
    metrics_path: '/metrics'
EOF

# Create basic AlertManager config
cat > alertmanager-config.yml << 'EOF'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'

receivers:
- name: 'web.hook'
  webhook_configs:
  - url: 'http://127.0.0.1:5001/'
EOF

# Create Grafana provisioning structure
mkdir -p grafana-provisioning/datasources
mkdir -p grafana-provisioning/dashboards

# Create datasource provisioning
cat > grafana-provisioning/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
EOF

# Create dashboard provisioning
cat > grafana-provisioning/dashboards/dashboard.yml << 'EOF'
apiVersion: 1

providers:
  - name: 'Yield Optimizer'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

# Copy dashboard if exists
if [ -f "k8s/monitoring/yield-optimizer-dashboard.json" ]; then
    cp k8s/monitoring/yield-optimizer-dashboard.json grafana-provisioning/dashboards/
    echo -e "${GREEN}✓${NC} Dashboard copied to provisioning directory"
fi

echo -e "${GREEN}✓${NC} Docker Compose monitoring setup created"
echo ""

# Check if monitoring is already running in Kubernetes
if kubectl get namespace monitoring >/dev/null 2>&1; then
    echo -e "${YELLOW}!${NC} Monitoring namespace exists in Kubernetes"
    echo "To check status: kubectl get all -n monitoring"
else
    echo -e "${BLUE}Kubernetes monitoring not deployed${NC}"
fi

echo ""
echo -e "${GREEN}=== Monitoring Options ===${NC}"
echo ""
echo "1. ${BLUE}Use Docker Compose (Recommended for local dev):${NC}"
echo "   docker-compose -f docker-compose-monitoring.yaml up -d"
echo "   "
echo "   Access:"
echo "   - Prometheus: http://localhost:9090"
echo "   - Grafana: http://localhost:3000 (admin/admin)"
echo "   - AlertManager: http://localhost:9093"
echo ""
echo "2. ${BLUE}Deploy to Kubernetes (when available):${NC}"
echo "   ./monitoring-deploy.sh"
echo ""
echo "3. ${BLUE}Quick Prometheus-only setup:${NC}"
echo "   docker run -d -p 9090:9090 -v \$(pwd)/prometheus-config.yml:/etc/prometheus/prometheus.yml prom/prometheus"
echo ""
echo -e "${YELLOW}Note:${NC} Make sure your yield-optimizer exposes metrics on port 8080"
echo "      The Docker Compose setup uses 'host.docker.internal:8080' to reach your local service"