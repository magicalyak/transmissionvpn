#!/bin/bash
set -e

# TransmissionVPN Monitoring Setup Script
# This script helps you set up monitoring for your TransmissionVPN container

echo "🚀 TransmissionVPN Monitoring Setup"
echo "===================================="

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Set Docker Compose command
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

echo "✅ Docker and Docker Compose are available"

# Check for environment configuration
check_env_config() {
    echo ""
    echo "🔧 Checking environment configuration..."
    
    if [ ! -f "../env.sample" ]; then
        echo "⚠️  env.sample file not found"
        return 1
    fi
    
    if [ ! -f "../.env" ]; then
        echo "📝 No .env file found. Creating from sample..."
        cp ../env.sample ../.env
        echo "✅ Created .env file from sample"
        echo ""
        echo "💡 You can customize the configuration by editing:"
        echo "   monitoring/.env"
        echo ""
        echo "🔒 Important: Change default passwords before production use!"
        echo "   - GRAFANA_ADMIN_PASSWORD"
        echo "   - INFLUXDB_ADMIN_PASSWORD"
        echo "   - INFLUXDB_TOKEN"
    else
        echo "✅ Environment file (.env) found"
    fi
}

# Function to check if TransmissionVPN is running
check_transmissionvpn() {
    if docker ps | grep -q transmissionvpn; then
        echo "✅ TransmissionVPN container is running"
        return 0
    else
        echo "⚠️  TransmissionVPN container is not running"
        echo "   Please start your TransmissionVPN container first"
        return 1
    fi
}

# Function to setup monitoring stack
setup_monitoring() {
    local stack_type=$1
    echo ""
    echo "📊 Setting up $stack_type monitoring stack..."
    
    case $stack_type in
        "prometheus")
            cd prometheus
            ;;
        "influxdb2")
            cd influxdb2
            ;;
        "complete")
            cd complete
            ;;
        *)
            echo "❌ Invalid stack type: $stack_type"
            exit 1
            ;;
    esac
    
    # Copy .env file to stack directory if it doesn't exist
    if [ ! -f ".env" ] && [ -f "../.env" ]; then
        echo "📋 Copying environment configuration..."
        cp ../.env .env
    fi
    
    # Start the stack
    echo "🔧 Starting monitoring services..."
    $DOCKER_COMPOSE up -d
    
    # Wait for services to start
    echo "⏳ Waiting for services to start..."
    sleep 30
    
    # Check service health
    check_services $stack_type
    
    cd ..
}

# Function to check service health
check_services() {
    local stack_type=$1
    echo ""
    echo "🔍 Checking service health..."
    
    case $stack_type in
        "prometheus")
            check_url "http://localhost:9090" "Prometheus"
            check_url "http://localhost:3000" "Grafana"
            ;;
        "influxdb2")
            check_url "http://localhost:8086" "InfluxDB2"
            check_url "http://localhost:3001" "Grafana"
            ;;
        "complete")
            check_url "http://localhost:9090" "Prometheus"
            check_url "http://localhost:8086" "InfluxDB2"
            check_url "http://localhost:3000" "Grafana"
            ;;
    esac
}

# Function to check URL availability
check_url() {
    local url=$1
    local service=$2
    
    if curl -s $url > /dev/null; then
        echo "✅ $service is accessible at $url"
    else
        echo "❌ $service is not accessible at $url"
    fi
}

# Function to show access information
show_access_info() {
    local stack_type=$1
    echo ""
    echo "🎉 Setup complete! Access your monitoring services:"
    echo "=================================================="
    
    case $stack_type in
        "prometheus")
            echo "📊 Prometheus: http://localhost:9090"
            echo "📈 Grafana: http://localhost:3000 (admin/admin)"
            ;;
        "influxdb2")
            echo "💾 InfluxDB2: http://localhost:8086 (admin/password123)"
            echo "📈 Grafana: http://localhost:3001 (admin/admin)"
            ;;
        "complete")
            echo "📊 Prometheus: http://localhost:9090"
            echo "💾 InfluxDB2: http://localhost:8086 (admin/password123)"
            echo "📈 Grafana: http://localhost:3000 (admin/admin)"
            echo "🔍 cAdvisor: http://localhost:8080"
            echo "📊 Node Exporter: http://localhost:9100"
            ;;
    esac
    
    echo ""
    echo "📚 Documentation: See monitoring/README.md for detailed instructions"
    echo "⚙️  Configuration: Edit monitoring/.env to customize settings"
}

# Function to show menu
show_menu() {
    echo ""
    echo "Please choose a monitoring stack:"
    echo "1) Prometheus + Grafana (recommended for beginners)"
    echo "2) InfluxDB2 + Telegraf + Grafana (advanced time-series)"
    echo "3) Complete Stack (all monitoring solutions)"
    echo "4) Check current status"
    echo "5) Stop all monitoring"
    echo "6) Edit environment configuration"
    echo "7) Exit"
    echo ""
}

# Function to stop monitoring
stop_monitoring() {
    echo "🛑 Stopping all monitoring services..."
    
    # Stop each stack
    for stack in prometheus influxdb2 complete; do
        if [ -d "$stack" ]; then
            echo "   Stopping $stack stack..."
            cd $stack
            $DOCKER_COMPOSE down 2>/dev/null || true
            cd ..
        fi
    done
    
    echo "✅ All monitoring services stopped"
}

# Function to check status
check_status() {
    echo "📊 Current monitoring service status:"
    echo "===================================="
    
    # Check for running monitoring containers
    if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(prometheus|grafana|influxdb2|telegraf|cadvisor|node-exporter|transmission-exporter)" > /dev/null; then
        echo "Running monitoring services:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(prometheus|grafana|influxdb2|telegraf|cadvisor|node-exporter|transmission-exporter)"
    else
        echo "❌ No monitoring services are currently running"
    fi
}

# Function to edit environment configuration
edit_env_config() {
    echo "⚙️  Environment Configuration"
    echo "============================="
    
    if [ ! -f "../.env" ]; then
        echo "📝 No .env file found. Creating from sample..."
        cp ../env.sample ../.env
    fi
    
    echo "📂 Environment file location: monitoring/.env"
    echo ""
    echo "🔧 Key variables to customize:"
    echo "   - GRAFANA_ADMIN_PASSWORD (change from default!)"
    echo "   - INFLUXDB_ADMIN_PASSWORD (change from default!)"
    echo "   - INFLUXDB_TOKEN (generate unique token!)"
    echo "   - Service ports (if needed)"
    echo ""
    
    if command -v nano &> /dev/null; then
        read -p "Open .env file in nano? (y/N): " edit_now
        if [[ $edit_now =~ ^[Yy]$ ]]; then
            nano ../.env
        fi
    else
        echo "💡 Edit the file manually: nano monitoring/.env"
    fi
}

# Main script
main() {
    # Check environment configuration
    check_env_config
    
    # Check TransmissionVPN status
    if ! check_transmissionvpn; then
        echo ""
        echo "ℹ️  You can still set up monitoring, but it won't collect data until TransmissionVPN is running."
        read -p "Continue anyway? (y/N): " continue_setup
        if [[ ! $continue_setup =~ ^[Yy]$ ]]; then
            echo "Setup cancelled."
            exit 0
        fi
    fi
    
    # Interactive menu
    while true; do
        show_menu
        read -p "Enter your choice (1-7): " choice
        
        case $choice in
            1)
                setup_monitoring "prometheus"
                show_access_info "prometheus"
                ;;
            2)
                setup_monitoring "influxdb2"
                show_access_info "influxdb2"
                ;;
            3)
                setup_monitoring "complete"
                show_access_info "complete"
                ;;
            4)
                check_status
                ;;
            5)
                stop_monitoring
                ;;
            6)
                edit_env_config
                ;;
            7)
                echo "👋 Goodbye!"
                exit 0
                ;;
            *)
                echo "❌ Invalid choice. Please enter 1-7."
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Run main function
main "$@" 