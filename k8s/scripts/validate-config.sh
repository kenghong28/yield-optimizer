#!/bin/bash

# Configuration validation script
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check environment argument
ENV=${1:-dev}
if [[ ! "$ENV" =~ ^(dev|prod)$ ]]; then
    echo -e "${RED}Error: Invalid environment '$ENV'${NC}"
    echo "Usage: $0 [dev|prod]"
    exit 1
fi

echo -e "${BLUE}=== Validating Configuration for $ENV Environment ===${NC}"
echo ""

# Paths
CHART_PATH="./helm/yield-optimizer"
VALUES_FILE="$CHART_PATH/values-$ENV.yaml"
BASE_VALUES="$CHART_PATH/values.yaml"

# Track validation status
VALIDATION_PASSED=true

# Function to check file exists
check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}✓${NC} Found: $1"
        return 0
    else
        echo -e "${RED}✗${NC} Missing: $1"
        VALIDATION_PASSED=false
        return 1
    fi
}

# Function to extract value from YAML
get_yaml_value() {
    local file=$1
    local key=$2
    grep "^$key:" "$file" 2>/dev/null | sed 's/.*: *//' | tr -d '"' || echo ""
}

# Function to check required value
check_required_value() {
    local file=$1
    local key=$2
    local value=$(get_yaml_value "$file" "$key")
    
    if [ -n "$value" ] && [ "$value" != "null" ] && [ "$value" != "" ]; then
        echo -e "${GREEN}✓${NC} $key: $value"
        return 0
    else
        echo -e "${RED}✗${NC} $key: NOT SET"
        VALIDATION_PASSED=false
        return 1
    fi
}

# 1. Check Files
echo "1. Checking configuration files..."
check_file "$BASE_VALUES"
check_file "$VALUES_FILE"
check_file "$CHART_PATH/Chart.yaml"
echo ""

# 2. Validate Helm Template
echo "2. Validating Helm template rendering..."
if helm template test-release $CHART_PATH -f $VALUES_FILE > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Helm template renders successfully"
else
    echo -e "${RED}✗${NC} Helm template rendering failed"
    echo "Error details:"
    helm template test-release $CHART_PATH -f $VALUES_FILE 2>&1 | grep -A5 "Error"
    VALIDATION_PASSED=false
fi
echo ""

# 3. Check Critical Configuration Values
echo "3. Checking critical configuration values..."

# Check image configuration
echo -e "${BLUE}Image Configuration:${NC}"
IMAGE_REPO=$(helm template test-release $CHART_PATH -f $VALUES_FILE --show-only templates/deployment-monitor.yaml | grep "image:" | sed 's/.*image: *//' | tr -d '"')
if [ -n "$IMAGE_REPO" ]; then
    echo -e "${GREEN}✓${NC} Image: $IMAGE_REPO"
else
    echo -e "${RED}✗${NC} Image repository not configured"
    VALIDATION_PASSED=false
fi

# Check replica count
REPLICAS=$(helm template test-release $CHART_PATH -f $VALUES_FILE --show-only templates/deployment-monitor.yaml | grep "replicas:" | sed 's/.*replicas: *//')
echo -e "${GREEN}✓${NC} Replicas: $REPLICAS"

echo ""

# 4. Check Resource Limits
echo "4. Checking resource configuration..."
RESOURCES=$(helm template test-release $CHART_PATH -f $VALUES_FILE --show-only templates/deployment-monitor.yaml | grep -A4 "resources:")
if echo "$RESOURCES" | grep -q "limits:"; then
    echo -e "${GREEN}✓${NC} Resource limits are set"
    echo "$RESOURCES" | grep -E "(cpu:|memory:)" | sed 's/^/    /'
else
    echo -e "${YELLOW}!${NC} No resource limits configured"
    if [ "$ENV" == "prod" ]; then
        echo -e "${RED}  Warning: Production should have resource limits${NC}"
        VALIDATION_PASSED=false
    fi
fi
echo ""

# 5. Check Service Configuration
echo "5. Checking service configuration..."
SERVICE_TYPE=$(helm template test-release $CHART_PATH -f $VALUES_FILE --show-only templates/service-monitor.yaml | grep "type:" | sed 's/.*type: *//')
SERVICE_PORT=$(helm template test-release $CHART_PATH -f $VALUES_FILE --show-only templates/service-monitor.yaml | grep -m1 "port:" | sed 's/.*port: *//')
echo -e "${GREEN}✓${NC} Service type: $SERVICE_TYPE"
echo -e "${GREEN}✓${NC} Service port: $SERVICE_PORT"
echo ""

# 6. Check Ingress Configuration
echo "6. Checking ingress configuration..."
if helm template test-release $CHART_PATH -f $VALUES_FILE | grep -q "kind: Ingress"; then
    INGRESS_HOST=$(helm template test-release $CHART_PATH -f $VALUES_FILE --show-only templates/ingress.yaml | grep "host:" | sed 's/.*host: *//' | head -1)
    if [ -n "$INGRESS_HOST" ]; then
        echo -e "${GREEN}✓${NC} Ingress host: $INGRESS_HOST"
        
        # Check TLS for production
        if [ "$ENV" == "prod" ]; then
            if helm template test-release $CHART_PATH -f $VALUES_FILE --show-only templates/ingress.yaml | grep -q "tls:"; then
                echo -e "${GREEN}✓${NC} TLS is configured for production"
            else
                echo -e "${RED}✗${NC} TLS not configured for production"
                VALIDATION_PASSED=false
            fi
        fi
    else
        echo -e "${YELLOW}!${NC} Ingress enabled but no host configured"
    fi
else
    echo -e "${YELLOW}!${NC} Ingress is disabled"
fi
echo ""

# 7. Check Database Configuration
echo "7. Checking database configuration..."
if helm template test-release $CHART_PATH -f $VALUES_FILE | grep -q "SUPABASE_URL"; then
    echo -e "${GREEN}✓${NC} Supabase URL is configured"
else
    echo -e "${YELLOW}!${NC} Supabase URL not found in ConfigMap"
fi

# Check if using external database
if grep -q "postgresql:\s*enabled:\s*false" $VALUES_FILE || grep -q "postgresql:\s*enabled:\s*false" $BASE_VALUES; then
    echo -e "${GREEN}✓${NC} Using external database (Supabase)"
else
    echo -e "${YELLOW}!${NC} Internal PostgreSQL is enabled (should use Supabase)"
fi
echo ""

# 8. Check Redis Configuration
echo "8. Checking Redis configuration..."
REDIS_ENABLED=$(helm template test-release $CHART_PATH -f $VALUES_FILE | grep -c "name: redis" || echo "0")
if [ "$REDIS_ENABLED" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Redis is configured"
    
    # Check persistence
    if helm template test-release $CHART_PATH -f $VALUES_FILE | grep -q "redis-data"; then
        echo -e "${GREEN}✓${NC} Redis persistence is enabled"
    else
        echo -e "${YELLOW}!${NC} Redis persistence is disabled"
    fi
else
    echo -e "${YELLOW}!${NC} Redis is not configured"
fi
echo ""

# 9. Check Security Settings
echo "9. Checking security settings..."

# Check ServiceAccount
if helm template test-release $CHART_PATH -f $VALUES_FILE | grep -q "serviceAccountName:"; then
    echo -e "${GREEN}✓${NC} ServiceAccount is configured"
else
    echo -e "${YELLOW}!${NC} No ServiceAccount configured"
fi

# Check SecurityContext
if helm template test-release $CHART_PATH -f $VALUES_FILE | grep -q "securityContext:"; then
    echo -e "${GREEN}✓${NC} SecurityContext is configured"
    
    # Check specific security settings
    if helm template test-release $CHART_PATH -f $VALUES_FILE | grep -A5 "securityContext:" | grep -q "runAsNonRoot: true"; then
        echo -e "${GREEN}✓${NC} Running as non-root user"
    else
        echo -e "${YELLOW}!${NC} Not configured to run as non-root"
    fi
else
    echo -e "${YELLOW}!${NC} No SecurityContext configured"
fi
echo ""

# 10. Check Monitoring
echo "10. Checking monitoring configuration..."
if helm template test-release $CHART_PATH -f $VALUES_FILE | grep -q "ServiceMonitor"; then
    echo -e "${GREEN}✓${NC} ServiceMonitor is configured for Prometheus"
else
    echo -e "${YELLOW}!${NC} No ServiceMonitor configured"
fi

if helm template test-release $CHART_PATH -f $VALUES_FILE | grep -q "/metrics"; then
    echo -e "${GREEN}✓${NC} Metrics endpoint is exposed"
else
    echo -e "${YELLOW}!${NC} No metrics endpoint found"
fi
echo ""

# 11. Environment-Specific Checks
echo "11. Environment-specific validation..."
if [ "$ENV" == "prod" ]; then
    echo -e "${BLUE}Production checks:${NC}"
    
    # Check replica count
    if [ "$REPLICAS" -lt 2 ]; then
        echo -e "${RED}✗${NC} Production should have at least 2 replicas (found: $REPLICAS)"
        VALIDATION_PASSED=false
    else
        echo -e "${GREEN}✓${NC} Adequate replicas for production"
    fi
    
    # Check autoscaling
    if helm template test-release $CHART_PATH -f $VALUES_FILE | grep -q "HorizontalPodAutoscaler"; then
        echo -e "${GREEN}✓${NC} HPA is configured for production"
    else
        echo -e "${YELLOW}!${NC} No autoscaling configured for production"
    fi
    
    # Check PDB
    if helm template test-release $CHART_PATH -f $VALUES_FILE | grep -q "PodDisruptionBudget"; then
        echo -e "${GREEN}✓${NC} PodDisruptionBudget is configured"
    else
        echo -e "${YELLOW}!${NC} No PodDisruptionBudget for production"
    fi
else
    echo -e "${BLUE}Development environment - relaxed checks${NC}"
fi
echo ""

# 12. Final Summary
echo -e "${BLUE}=== Configuration Validation Summary ===${NC}"
if [ "$VALIDATION_PASSED" = true ]; then
    echo -e "${GREEN}✓ Configuration validation passed for $ENV environment!${NC}"
    echo ""
    echo "Configuration is ready for deployment."
else
    echo -e "${RED}✗ Configuration validation failed!${NC}"
    echo ""
    echo "Please fix the issues above before deploying."
    exit 1
fi

# Show rendered manifests count
MANIFEST_COUNT=$(helm template test-release $CHART_PATH -f $VALUES_FILE | grep -c "^---$" || echo "0")
echo ""
echo -e "${BLUE}Info:${NC} Will create $MANIFEST_COUNT Kubernetes resources"

# Offer to show full rendered output
echo ""
echo "To see the full rendered manifests, run:"
echo "  helm template test-release $CHART_PATH -f $VALUES_FILE"