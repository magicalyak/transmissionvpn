# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 4.0.6-rX (latest) | :white_check_mark: |
| < 4.0.6-r15 | :x: |

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it by:

1. **For critical vulnerabilities**: Email magicalyak@users.noreply.github.com with details
2. **For non-critical issues**: Open an issue on GitHub with the `security` label

Please include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if available)

We take all security reports seriously and aim to respond within 48 hours.

## Security Measures

This image implements multiple security layers:

### 1. VPN Kill Switch
- Strict iptables rules prevent any traffic leaks if VPN disconnects
- DNS leak protection enabled by default
- All non-VPN traffic is blocked except for management UI
- Automatic VPN monitoring and recovery

### 2. Container Security
- Based on Alpine Linux for minimal attack surface
- Regular security updates via automated builds
- Non-root user execution where possible
- Removed unnecessary packages from runtime
- Pinned base image versions for better security tracking

### 3. Dependency Management
- Automated dependency updates via Dependabot
- Docker Scout scanning enabled for vulnerability detection
- Regular package updates (`apk upgrade`)
- Security scanning in CI/CD pipeline (Trivy)

### 4. Network Security
- Transmission UI authentication support
- IP whitelisting for access control
- Privoxy proxy for additional privacy (optional)
- Separate network interfaces for VPN and management

## Security Updates

- Base image updated with each release
- Alpine packages upgraded during every build
- Security patches applied automatically
- CVE monitoring through Docker Scout and Trivy

## Security Best Practices for Users

1. **Always use VPN credentials** - Never run without VPN protection
2. **Enable authentication**:
   ```yaml
   TRANSMISSION_RPC_AUTHENTICATION_REQUIRED: true
   TRANSMISSION_RPC_USERNAME: admin
   TRANSMISSION_RPC_PASSWORD: secure-password-here
   ```
3. **Restrict access** - Configure `TRANSMISSION_RPC_HOST_WHITELIST`
4. **Use Docker secrets** for sensitive data:
   ```yaml
   FILE__VPN_USER: /run/secrets/vpn_user
   FILE__VPN_PASS: /run/secrets/vpn_pass
   ```
5. **Regular updates** - Pull latest image for security patches:
   ```bash
   docker pull magicalyak/transmissionvpn:latest
   ```
6. **Monitor health** - Check container health status regularly

## Known Security Considerations

- Some CVEs may originate from the upstream linuxserver.io base image
- Alpine Linux packages might have pending patches
- VPN provider security depends on your chosen provider
- Exposed ports should be minimized in production

## Security Scanning

This image is regularly scanned using:
- **Docker Scout** - Integrated vulnerability scanning on Docker Hub
- **Trivy** - Security scanning in GitHub Actions
- **Dependabot** - Automated dependency updates
- **Hadolint** - Dockerfile best practices

Current security efforts focus on:
- Minimizing CVE count through regular updates
- Reducing attack surface by removing unnecessary components
- Implementing defense-in-depth strategies

## Verification

To verify the kill switch is working:
```bash
# Check the comprehensive guide
cat docs/KILLSWITCH_VERIFICATION.md

# Quick test
docker exec transmission iptables -L -v -n | grep DROP
```

## Security Contact

- GitHub Issues: https://github.com/magicalyak/transmissionvpn/issues
- Email: magicalyak@users.noreply.github.com (for sensitive issues)