#!/bin/bash
set -e

# Configuration - Update these for each release
VERSION="v4.0.6-r15"  # Update this for next release
IMAGE_NAME="magicalyak/transmissionvpn"
BRANCH="main"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 TransmissionVPN Release Script${NC}"
echo -e "${BLUE}===================================${NC}"
echo -e "Version: ${GREEN}${VERSION}${NC}"
echo -e "Image:   ${GREEN}${IMAGE_NAME}${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}📋 Checking prerequisites...${NC}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running. Please start Docker and try again.${NC}"
    exit 1
fi

# Check if we're on the right branch
current_branch=$(git branch --show-current)
if [[ "$current_branch" != "$BRANCH" ]]; then
    echo -e "${RED}❌ Not on $BRANCH branch. Current branch: $current_branch${NC}"
    echo -e "   Switch to $BRANCH branch: ${YELLOW}git checkout $BRANCH${NC}"
    exit 1
fi

# Check if tag already exists
if git tag -l | grep -q "^${VERSION}$"; then
    echo -e "${RED}❌ Tag ${VERSION} already exists!${NC}"
    echo -e "   To recreate: ${YELLOW}git tag -d ${VERSION} && git push origin :refs/tags/${VERSION}${NC}"
    exit 1
fi

# Check for uncommitted changes
if [[ -n $(git status --porcelain) ]]; then
    echo -e "${YELLOW}⚠️  Uncommitted changes detected:${NC}"
    git status --short
    echo ""
    read -p "Continue with uncommitted changes? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}❌ Aborted. Please commit your changes first.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo ""

# Show what will be released
echo -e "${YELLOW}📦 Release Summary${NC}"
echo -e "${YELLOW}==================${NC}"
echo -e "Version:     ${GREEN}${VERSION}${NC}"
echo -e "Branch:      ${GREEN}${BRANCH}${NC}"
echo -e "Image:       ${GREEN}${IMAGE_NAME}${NC}"
echo -e "Platforms:   ${GREEN}linux/amd64, linux/arm64${NC}"
echo ""
echo -e "${BLUE}💡 Pre-Release Testing Available:${NC}"
echo -e "   For testing before release, create a release branch:"
echo -e "   ${YELLOW}git checkout -b release/${VERSION}${NC}"
echo -e "   ${YELLOW}git push origin release/${VERSION}${NC}"
echo -e "   This will trigger RC build on GHCR: ${BLUE}ghcr.io/${IMAGE_NAME}:rc-latest${NC}"
echo ""

# Create commit if there are changes
if [[ -n $(git status --porcelain) ]]; then
    echo -e "${BLUE}📝 Committing changes...${NC}"
    git add .
    
    # Extract version number for commit message
    VERSION_NUM=${VERSION#v}
    
    git commit -m "Release ${VERSION}

- Enhanced Docker Hub tag management
- Improved GitHub Actions workflow with validation
- Better error handling and debugging
- Multi-architecture support for linux/amd64 and linux/arm64
- Comprehensive monitoring with Prometheus and Grafana
- Clean release tags only (no development clutter)
- Release candidate workflow for pre-release testing"
fi

# Create and push tag
echo -e "${BLUE}🏷️  Creating tag ${VERSION}...${NC}"
git tag -a "${VERSION}" -m "Release ${VERSION}

## 🎉 TransmissionVPN ${VERSION}

### 🚀 Features
- Multi-architecture Docker images (linux/amd64, linux/arm64)
- Enhanced monitoring with custom Python metrics server
- Beautiful Grafana dashboards for transmission monitoring
- Comprehensive health checks and VPN status monitoring
- Integration with existing Prometheus/Grafana setups
- Release candidate workflow for pre-release testing

### 🐳 Docker Images
- **Docker Hub**: magicalyak/transmissionvpn:${VERSION#v}
- **GitHub Container Registry**: ghcr.io/magicalyak/transmissionvpn:${VERSION#v}
- **Latest**: magicalyak/transmissionvpn:latest
- **Stable**: magicalyak/transmissionvpn:stable

### 📊 Monitoring Options
1. **Built-in Metrics** (⭐ Simple) - Just enable METRICS_ENABLED=true
2. **Existing Prometheus/Grafana** (⭐⭐ Easy) - Add to current infrastructure  
3. **Complete InfluxDB2 Stack** (⭐⭐⭐ Advanced) - Full new monitoring stack

### 🧪 Pre-Release Testing
- Release candidates available on GHCR for testing
- Create release/* branches to trigger RC builds
- Test before pushing to production Docker Hub

### 🔧 Key Improvements
- Clean Docker Hub tags (no more development clutter)
- Enhanced GitHub Actions with validation and error handling
- Comprehensive documentation and troubleshooting guides
- Repository cleanup and consolidation

See CHANGELOG.md for complete details."

echo -e "${GREEN}✅ Git tag created successfully${NC}"
echo ""

# Show next steps
echo -e "${BLUE}🚀 Next Steps${NC}"
echo -e "${BLUE}=============${NC}"
echo -e "1. Push the Git tag:    ${YELLOW}git push origin ${VERSION}${NC}"
echo -e "2. GitHub Actions will automatically:"
echo -e "   - Build multi-arch Docker images"
echo -e "   - Push to Docker Hub and GHCR"
echo -e "   - Run security scans"
echo -e "   - Create GitHub release"
echo -e "3. Monitor the build:   ${BLUE}https://github.com/magicalyak/transmissionvpn/actions${NC}"
echo -e "4. Check Docker Hub:    ${BLUE}https://hub.docker.com/r/magicalyak/transmissionvpn/tags${NC}"
echo ""

# Ask if user wants to push automatically
read -p "Push Git tag now to trigger automated release? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}📤 Pushing Git tag...${NC}"
    git push origin "${VERSION}"
    
    echo ""
    echo -e "${GREEN}🎉 Release ${VERSION} triggered successfully!${NC}"
    echo -e "GitHub Actions: ${BLUE}https://github.com/magicalyak/transmissionvpn/actions${NC}"
    echo -e "Docker Hub:     ${BLUE}https://hub.docker.com/r/magicalyak/transmissionvpn/tags${NC}"
    echo ""
    echo -e "${YELLOW}⏱️  The build will take ~10-15 minutes to complete${NC}"
    echo -e "${YELLOW}📧 You'll get a GitHub notification when it's done${NC}"
else
    echo -e "${YELLOW}ℹ️  Manual push required:${NC}"
    echo -e "   ${BLUE}git push origin ${VERSION}${NC}"
fi

echo ""
echo -e "${GREEN}✨ Release script completed!${NC}" 