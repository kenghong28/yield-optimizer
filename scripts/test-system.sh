#!/bin/bash

set -e

echo "🚀 Starting HyperEVM Yield Optimizer Test"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

print_status "Starting test databases..."

# Start test databases
docker-compose -f docker-compose.test.yml up -d

# Wait for databases to be ready
print_status "Waiting for databases to be ready..."
sleep 10

# Check if PostgreSQL is ready
until docker-compose -f docker-compose.test.yml exec -T postgres-test pg_isready -U postgres; do
    print_warning "Waiting for PostgreSQL..."
    sleep 2
done

print_status "PostgreSQL is ready!"

# Check if Redis is ready
until docker-compose -f docker-compose.test.yml exec -T redis-test redis-cli ping; do
    print_warning "Waiting for Redis..."
    sleep 2
done

print_status "Redis is ready!"

# Run database migrations
print_status "Running database migrations..."
docker-compose -f docker-compose.test.yml exec -T postgres-test psql -U postgres -d yield_optimizer_test -f - < scripts/migrate.sql

if [ $? -eq 0 ]; then
    print_status "Database migrations completed successfully!"
else
    print_error "Database migrations failed!"
    exit 1
fi

# Initialize Go modules
print_status "Initializing Go modules..."
go mod tidy

# Generate sqlc code
print_status "Generating sqlc code..."
sqlc generate

if [ $? -eq 0 ]; then
    print_status "sqlc code generation completed!"
else
    print_error "sqlc code generation failed!"
    exit 1
fi

# Run the test monitor
print_status "Starting price monitoring test..."
echo ""
echo "📊 Running price monitoring system for 30 seconds..."
echo "   - Monitoring HyperEVM blockchain"
echo "   - Testing price oracle functionality"
echo "   - Verifying database connections"
echo ""

go run cmd/test-monitor/main.go

if [ $? -eq 0 ]; then
    echo ""
    print_status "✅ Test completed successfully!"
    echo ""
    echo "🎉 System Status:"
    echo "   ✅ PostgreSQL connection: Working"
    echo "   ✅ Redis connection: Working" 
    echo "   ✅ HyperEVM connection: Working"
    echo "   ✅ Price oracle: Working"
    echo "   ✅ Database queries: Working"
    echo ""
    print_status "The price monitoring and range detection system is ready!"
else
    print_error "❌ Test failed!"
    exit 1
fi

# Cleanup option
echo ""
read -p "Do you want to stop the test databases? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Stopping test databases..."
    docker-compose -f docker-compose.test.yml down
    print_status "Test databases stopped."
else
    print_status "Test databases are still running."
    print_status "You can access:"
    print_status "  - PostgreSQL: localhost:5432 (postgres/password)"
    print_status "  - Redis: localhost:6379"
    print_status "  - RedisInsight: http://localhost:8001"
    print_status ""
    print_status "To stop later: docker-compose -f docker-compose.test.yml down"
fi