#!/bin/bash
# Quick health check script for Freddy server
# Run this to verify all services are healthy

echo "==================================="
echo "Freddy Server Health Check"
echo "==================================="
echo ""

# Check Docker Compose is running
if ! docker-compose ps > /dev/null 2>&1; then
    echo "❌ Docker Compose not found or not in correct directory"
    echo "   Run this script from /home/jordan/freddy/"
    exit 1
fi

echo "📊 Service Status:"
echo ""
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(NAMES|nginx|photoprism|nextcloud|homeassistant|authelia|redis|postgres|audiobookshelf)"

echo ""
echo "==================================="
echo "🔍 Detailed Health Status:"
echo "==================================="
echo ""

# Function to check individual service health
check_health() {
    local service=$1
    local status=$(docker inspect --format='{{.State.Health.Status}}' $service 2>/dev/null)
    
    if [ -z "$status" ]; then
        status="no healthcheck"
        echo "⚪ $service: $status"
    elif [ "$status" = "healthy" ]; then
        echo "✅ $service: $status"
    elif [ "$status" = "starting" ]; then
        echo "🟡 $service: $status"
    else
        echo "❌ $service: $status"
    fi
}

# Check all services
check_health "nginx"
check_health "photoprism"
check_health "photoprism-postgres"
check_health "nextcloud"
check_health "nextcloud-postgres"
check_health "homeassistant"
check_health "authelia"
check_health "authelia-postgres"
check_health "redis"
check_health "audiobookshelf"

echo ""
echo "==================================="
echo "🌐 Service Accessibility:"
echo "==================================="
echo ""

# Test nginx dashboard
if curl -k -f -s https://localhost/dashboard/index.html > /dev/null 2>&1; then
    echo "✅ Nginx Dashboard: Accessible"
else
    echo "❌ Nginx Dashboard: Not accessible"
fi

# Test individual services
if curl -f -s http://localhost:2342/api/v1/status > /dev/null 2>&1; then
    echo "✅ PhotoPrism: Accessible"
else
    echo "❌ PhotoPrism: Not accessible"
fi

if curl -k -f -s https://localhost:8443/status.php > /dev/null 2>&1; then
    echo "✅ Nextcloud: Accessible"
else
    echo "❌ Nextcloud: Not accessible"
fi

if curl -f -s http://localhost:8123/manifest.json > /dev/null 2>&1; then
    echo "✅ Home Assistant: Accessible"
else
    echo "❌ Home Assistant: Not accessible"
fi

if curl -f -s http://localhost:9091/api/health > /dev/null 2>&1; then
    echo "✅ Authelia: Accessible"
else
    echo "❌ Authelia: Not accessible"
fi

if curl -f -s http://localhost:13378/healthcheck > /dev/null 2>&1; then
    echo "✅ Audiobookshelf: Accessible"
else
    echo "⚪ Audiobookshelf: Unknown (endpoint may not exist)"
fi


echo ""
echo "==================================="
echo "💾 Database Status:"
echo "==================================="
echo ""

# Check PostgreSQL databases
if docker exec photoprism-postgres pg_isready -U photoprism -d photoprism > /dev/null 2>&1; then
    echo "✅ PhotoPrism Database: Ready"
else
    echo "❌ PhotoPrism Database: Not ready"
fi

if docker exec nextcloud-postgres pg_isready -U nextcloud -d nextcloud > /dev/null 2>&1; then
    echo "✅ Nextcloud Database: Ready"
else
    echo "❌ Nextcloud Database: Not ready"
fi

if docker exec authelia-postgres pg_isready -U authelia -d authelia > /dev/null 2>&1; then
    echo "✅ Authelia Database: Ready"
else
    echo "❌ Authelia Database: Not ready"
fi

# Check Redis
if docker exec redis redis-cli ping > /dev/null 2>&1; then
    echo "✅ Redis: Ready"
else
    echo "❌ Redis: Not ready"
fi

echo ""
echo "==================================="
echo "⚠️  Common Issues:"
echo "==================================="
echo ""

# Check PhotoPrism database driver
if docker logs photoprism 2>&1 | grep -q "using sqlite"; then
    echo "⚠️  PhotoPrism is using SQLite instead of PostgreSQL!"
    echo "   See HEALTH_CHECK_IMPROVEMENTS.md for migration steps"
fi

# Check for unhealthy services
unhealthy=$(docker ps --filter "health=unhealthy" --format "{{.Names}}")
if [ -n "$unhealthy" ]; then
    echo "⚠️  Unhealthy services detected: $unhealthy"
    echo "   Check logs with: docker logs <service_name>"
fi

# Check startup time
if docker inspect nginx --format='{{.State.StartedAt}}' > /dev/null 2>&1; then
    started=$(docker inspect nginx --format='{{.State.StartedAt}}')
    echo ""
    echo "ℹ️  Nginx started at: $started"
fi

echo ""
echo "==================================="
echo "📝 Quick Commands:"
echo "==================================="
echo ""
echo "  Restart all:       docker-compose restart"
echo "  View logs:         docker logs <service> --tail 50"
echo "  Manual health:     docker exec <service> <healthcheck_cmd>"
echo "  Full status:       docker-compose ps"
echo ""
