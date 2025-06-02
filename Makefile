# TransmissionVPN Makefile
# Simple commands to help you get started

.PHONY: help setup start stop logs clean build

# Default target
help:
	@echo "TransmissionVPN Docker Container"
	@echo ""
	@echo "Available commands:"
	@echo "  setup     - Create directories and copy sample files"
	@echo "  start     - Start the container with docker-compose"
	@echo "  stop      - Stop the container"
	@echo "  restart   - Restart the container"
	@echo "  logs      - Show container logs"
	@echo "  shell     - Open shell in running container"
	@echo "  status    - Show container status and health"
	@echo "  clean     - Stop and remove container"
	@echo "  build     - Build the Docker image locally"
	@echo ""
	@echo "Quick start:"
	@echo "  1. make setup"
	@echo "  2. Edit .env file with your VPN settings"
	@echo "  3. Add your VPN config to config/openvpn/"
	@echo "  4. make start"

# Setup directories and files
setup:
	@echo "Setting up TransmissionVPN..."
	@mkdir -p config/openvpn config/wireguard downloads watch
	@if [ ! -f .env ]; then cp .env.sample .env; echo "Created .env file - please edit it with your settings"; fi
	@echo "Setup complete!"
	@echo ""
	@echo "Next steps:"
	@echo "1. Edit .env file with your VPN credentials"
	@echo "2. Copy your VPN config file to config/openvpn/ or config/wireguard/"
	@echo "3. Run 'make start' to start the container"

# Start container
start:
	@echo "Starting TransmissionVPN..."
	@docker-compose up -d
	@echo "Container started!"
	@echo "Web UI: http://localhost:9091"
	@echo "Logs: make logs"

# Stop container
stop:
	@echo "Stopping TransmissionVPN..."
	@docker-compose down

# Restart container
restart: stop start

# Show logs
logs:
	@docker-compose logs -f

# Open shell in container
shell:
	@docker exec -it transmissionvpn /bin/bash

# Show status
status:
	@echo "=== Container Status ==="
	@docker ps | grep transmissionvpn || echo "Container not running"
	@echo ""
	@echo "=== Health Check ==="
	@docker exec transmissionvpn /root/healthcheck.sh 2>/dev/null || echo "Health check failed or container not running"
	@echo ""
	@echo "=== External IP ==="
	@docker exec transmissionvpn curl -s ifconfig.me 2>/dev/null || echo "Cannot check IP - container not running or no internet"

# Clean up
clean:
	@echo "Cleaning up TransmissionVPN..."
	@docker-compose down -v
	@docker image prune -f

# Build image locally
build:
	@echo "Building TransmissionVPN image..."
	@docker build -t magicalyak/transmissionvpn:local .
	@echo "Build complete! Use 'magicalyak/transmissionvpn:local' as image in docker-compose.yml"

# Development helpers
dev-logs:
	@docker-compose logs -f --tail=100

dev-shell:
	@docker exec -it transmissionvpn /bin/bash

dev-health:
	@docker exec transmissionvpn /root/healthcheck.sh

dev-ip:
	@docker exec transmissionvpn curl ifconfig.me
