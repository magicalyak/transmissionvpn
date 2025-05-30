# NZBGet + VPN Docker Image

A Dockerized NZBGet client with built-in OpenVPN support, based on the [linuxserver/nzbget](https://hub.docker.com/r/linuxserver/nzbget) image.

✅ Based on `ghcr.io/linuxserver/nzbget`  
🔐 OpenVPN client integration  
🚀 Automatically builds against **NZBGet v25**  
📦 Tags Docker images by full version (e.g. `v25.0`)  
💡 Includes health checks and custom init scripts

---

## 🛠️ Directory Structure

.
├── build/
│   └── version-tag-push.sh        # Auto version/tag/push script
├── config/
│   └── openvpn/
│       └── atl-009.ovpn           # Your PrivadoVPN .ovpn config
├── root/
│   ├── init.sh                    # Container entrypoint
│   └── healthcheck.sh            # Optional healthcheck script
├── Dockerfile                     # Main image build
├── Makefile                       # Build helper
├── README.md
└── LICENSE.md

---

## 🧱 Build & Tag the Image

```bash
make tag-push
```

This runs build/version-tag-push.sh, which:
	•	Extracts NZBGET_VERSION from the Dockerfile
	•	Tags the image as magicalyak/nzbgetvpn:vX.Y.Z and latest
	•	Prompts for Docker Hub login if not authenticated
	•	Pushes the image to Docker Hub

## 🚀 Run the Container

Example docker run:

```bash
docker run --cap-add=NET_ADMIN \
  -v /path/to/config:/config \
  -v /path/to/downloads:/downloads \
  -v /etc/localtime:/etc/localtime:ro \
  -v $(pwd)/config/openvpn/atl-009.ovpn:/etc/openvpn/custom.ovpn:ro \
  -e VPN_ENABLED=true \
  -e VPN_CONFIG=/etc/openvpn/custom.ovpn \
  -e VPN_USER=yourvpnusername \
  -e VPN_PASS=yourvpnpassword \
  -p 6789:6789 \
  --restart unless-stopped \
  --name nzbgetvpn \
  magicalyak/nzbgetvpn:latest
```

⸻

## 🔍 Health Check

A simple healthcheck.sh script is included to monitor VPN tunnel and NZBGet availability. Customize as needed.

⸻

## 🔐 VPN Support
	•	Compatible with OpenVPN providers (e.g., PrivadoVPN)
	•	Uses .ovpn configs + environment variables for credentials
	•	Launches VPN tunnel before starting NZBGet

⸻

## 🧪 Debugging

Check your external IP to verify tunnel is active:

```bash
docker exec -it nzbgetvpn curl ifconfig.me
```

Log container output:

```bash
docker logs -f nzbgetvpn
```

⸻

## 📄 License

MIT License. See [License](./LICENSE) file for details.

⸻

## ✍️ Author

Maintained by [magicalyak](https://github.com/magicalyak).

