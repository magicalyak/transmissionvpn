IMAGE_NAME ?= transmissionvpn
CONTAINER_NAME ?= transmissionvpn-container

# Attempt to read PRIVOXY_PORT from .env file, default to 8118 if not found or .env is missing
# This ensures PRIVOXY_HOST_PORT aligns with the internal PRIVOXY_PORT set in .env
PRIVOXY_PORT_FROM_ENV := $(shell if [ -f .env ]; then grep '^PRIVOXY_PORT=' .env | cut -d= -f2; fi)
PRIVOXY_HOST_PORT ?= $(PRIVOXY_PORT_FROM_ENV)
PRIVOXY_HOST_PORT ?= 8118 # Fallback if not in .env or .env doesn't exist

.PHONY: all build run run-openvpn run-wireguard logs stop shell clean help

all: build

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all                Build the Docker image (default)."
	@echo "  build              Build the Docker image."
	@echo "  run                Run the Docker container with OpenVPN (example, edit .env first)."
	@echo "  run-openvpn        Alias for 'run'."
	@echo "  run-wireguard      Run the Docker container with WireGuard (example, edit .env and WireGuard config)."
	@echo "  logs               Follow logs of the running container."
	@echo "  stop               Stop and remove the running container."
	@echo "  shell              Get a shell inside the running container."
	@echo "  clean              Remove stopped containers and the Docker image."

build:
	@echo "Building Docker image $(IMAGE_NAME)..."
	docker build -t $(IMAGE_NAME) .

run: run-openvpn

run-openvpn:
	@echo "Running container $(CONTAINER_NAME) with OpenVPN..."
	@echo "Ensure your .env file has VPN_USER, VPN_PASS, and VPN_CONFIG set correctly."
	@echo "VPN_CONFIG should point to an .ovpn file in ./config/openvpn/"
	docker run -d \
		--name $(CONTAINER_NAME) \
		--rm \
		--cap-add=NET_ADMIN \
		--device=/dev/net/tun \
		-p 9091:9091 \
		-p $(PRIVOXY_HOST_PORT):$(PRIVOXY_HOST_PORT) \
		-v "$(shell pwd)/config:/config" \
		-v "$(shell pwd)/downloads:/downloads" \
		-v "$(shell pwd)/watch:/watch" \
		--env-file .env \
		-e VPN_CLIENT=openvpn \
		$(IMAGE_NAME)

run-wireguard:
	@echo "Running container $(CONTAINER_NAME) with WireGuard..."
	@echo "Ensure your .env file has VPN_CONFIG set (e.g., /config/wireguard/wg0.conf)."
	@echo "And that the actual WireGuard config (e.g., wg0.conf) exists in ./config/wireguard/"
	docker run -d \
		--name $(CONTAINER_NAME) \
		--rm \
		--cap-add=NET_ADMIN \
		--cap-add=SYS_MODULE \
		--sysctl="net.ipv4.conf.all.src_valid_mark=1" \
		--sysctl="net.ipv6.conf.all.disable_ipv6=0" \
		--device=/dev/net/tun \
		-p 9091:9091 \
		-p $(PRIVOXY_HOST_PORT):$(PRIVOXY_HOST_PORT) \
		-v "$(shell pwd)/config:/config" \
		-v "$(shell pwd)/downloads:/downloads" \
		-v "$(shell pwd)/watch:/watch" \
		--env-file .env \
		-e VPN_CLIENT=wireguard \
		$(IMAGE_NAME)

logs:
	@echo "Following logs for $(CONTAINER_NAME)..."
	docker logs -f $(CONTAINER_NAME)

stop:
	@echo "Stopping and removing $(CONTAINER_NAME)..."
	docker stop $(CONTAINER_NAME) || true
	docker rm -f $(CONTAINER_NAME) || true

shell:
	@echo "Opening shell in $(CONTAINER_NAME)..."
	docker exec -it $(CONTAINER_NAME) /bin/bash

clean:
	@echo "Cleaning up..."
	docker stop $(CONTAINER_NAME) || true 
	# docker rm $(CONTAINER_NAME) || true # Not needed due to --rm
	@read -p "Remove Docker image $(IMAGE_NAME)? [y/N] " choice; \
	case "$$choice" in \
	  y|Y ) docker rmi $(IMAGE_NAME) || true;; \
	  * ) echo "Skipping image removal.";; \
	esac
