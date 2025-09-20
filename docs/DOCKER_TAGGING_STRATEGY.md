# Docker Tagging Strategy

## Overview

This document defines the tagging strategy for the transmissionvpn Docker images published to Docker Hub and GitHub Container Registry.

## Versioning Scheme

We follow the **linuxserver.io transmission** versioning with our own patch increments:

```
v{TRANSMISSION_VERSION}-r{PATCH_NUMBER}
```

Example: `v4.0.6-r21`

## Docker Hub Configuration

### Important: Use GitHub Actions Only

**DO NOT** use Docker Hub's automated build feature. Our GitHub Actions workflow handles:
- Multi-architecture builds (amd64, arm64)
- Proper tagging across multiple registries
- Security scanning
- Automated testing

If Docker Hub automated builds are currently enabled, **disable them** to avoid conflicts.

## Tagging Strategy

When you create a git tag like `v4.0.6-r21` and push it, the GitHub Actions workflow automatically creates these Docker tags:

| Docker Tag | Description | Example |
|------------|-------------|---------|
| `4.0.6-r21` | Full version with patch | Exact version |
| `4.0.6` | Base transmission version | Latest patch for this version |
| `4.0` | Minor version | Latest 4.0.x release |
| `4` | Major version | Latest 4.x release |
| `latest` | Latest stable release | Most recent version tag |
| `stable` | Stable release alias | Same as latest |
| `main` | Main branch builds | Development builds |

## Release Process

### 1. Check Current Version
```bash
git describe --tags --abbrev=0
# Example output: v4.0.6-r20
```

### 2. Create New Tag
```bash
# Increment the patch number
git tag -a v4.0.6-r21 -m "Release v4.0.6-r21: Description of changes"
```

### 3. Push Tag to GitHub
```bash
git push origin v4.0.6-r21
```

### 4. GitHub Actions Automatically:
- Builds multi-architecture images (amd64, arm64)
- Creates all convenience tags (4.0.6-r21, 4.0.6, 4.0, 4, latest, stable)
- Pushes to Docker Hub and GitHub Container Registry
- Runs security scans
- Updates Docker Hub README
- Creates GitHub Release

## Important Rules

### DO:
- ✅ Follow the `v{TRANSMISSION_VERSION}-r{PATCH}` format exactly
- ✅ Check upstream linuxserver.io transmission version before updating base version
- ✅ Increment patch number for our fixes
- ✅ Create meaningful tag messages
- ✅ Let GitHub Actions handle all Docker operations

### DON'T:
- ❌ Create tags like `v4.0.7` unless linuxserver.io releases transmission 4.0.7
- ❌ Use Docker Hub automated builds
- ❌ Manually push to Docker Hub
- ❌ Skip version numbers
- ❌ Use tags without the `v` prefix

## Checking Upstream Version

Before changing the base version (e.g., from 4.0.6 to 4.0.7), verify the upstream version:

```bash
# Check linuxserver.io transmission releases
curl -s https://api.github.com/repos/linuxserver/docker-transmission/releases/latest | jq -r .tag_name
```

## Docker Registries

Images are published to:
1. **Docker Hub**: `docker.io/magicalyak/transmissionvpn`
2. **GitHub Container Registry**: `ghcr.io/magicalyak/transmissionvpn`

## Pulling Images

Users can pull images using any of the tags:

```bash
# Latest stable version
docker pull magicalyak/transmissionvpn:latest

# Specific version
docker pull magicalyak/transmissionvpn:4.0.6-r21

# Latest 4.0.x version
docker pull magicalyak/transmissionvpn:4.0

# From GitHub Container Registry
docker pull ghcr.io/magicalyak/transmissionvpn:latest
```

## Development Builds

Commits to `main` branch automatically create:
- `magicalyak/transmissionvpn:main` - Latest main branch build
- No version tags are created for development builds

## Troubleshooting

### If tags aren't appearing on Docker Hub:
1. Check GitHub Actions workflow run: https://github.com/magicalyak/transmissionvpn/actions
2. Verify Docker Hub credentials in repository secrets
3. Ensure tag follows correct format `v{X.Y.Z}-r{N}`

### If automated builds are running on Docker Hub:
1. Go to: https://hub.docker.com/repository/docker/magicalyak/transmissionvpn/builds/edit
2. Delete all build rules
3. Disable automated builds

## Version History Tracking

Track all releases in `VERSIONING.md` with format:
```
- `v4.0.6-r21` - Brief description of changes
```