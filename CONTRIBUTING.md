# Contributing to TransmissionVPN

Thank you for your interest in contributing to TransmissionVPN! This document provides guidelines and information for contributors.

## 🚀 Quick Start

1. **Fork the repository** on GitHub
2. **Clone your fork** locally
3. **Create a feature branch** from `main`
4. **Make your changes** and test them
5. **Submit a pull request** with a clear description

## 📋 Ways to Contribute

### 🐛 Bug Reports
- Use our [bug report template](.github/ISSUE_TEMPLATE/bug_report.yml)
- Include system information, steps to reproduce, and expected vs actual behavior
- Check existing issues to avoid duplicates

### ✨ Feature Requests
- Use our [feature request template](.github/ISSUE_TEMPLATE/feature_request.yml)
- Describe the problem you're trying to solve
- Explain your proposed solution and alternatives considered

### 📚 Documentation
- Fix typos, improve clarity, or add missing information
- Update examples and configuration guides
- Enhance troubleshooting documentation

### 🛠️ Code Contributions
- Bug fixes and feature implementations
- Performance improvements
- Security enhancements
- Test coverage improvements

## 🔧 Development Setup

### Prerequisites
- Docker and Docker Compose
- Git
- Text editor or IDE
- Basic knowledge of shell scripting

### Local Development

1. **Clone the repository:**
   ```bash
   git clone https://github.com/magicalyak/transmissionvpn.git
   cd transmissionvpn
   ```

2. **Set up development environment:**
   ```bash
   make setup
   cp .env.sample .env
   # Edit .env with test VPN credentials
   ```

3. **Build and test locally:**
   ```bash
   make build
   make start
   make logs
   ```

4. **Run tests:**
   ```bash
   # Test container startup
   docker exec transmissionvpn /root/healthcheck.sh
   
   # Test VPN connectivity
   docker exec transmissionvpn curl ifconfig.me
   
   # Test Transmission API
   docker exec transmissionvpn curl -f http://localhost:9091/transmission/web/
   ```

## 📝 Code Standards

### Shell Scripts
- Use `#!/bin/bash` for bash scripts
- Follow [ShellCheck](https://www.shellcheck.net/) recommendations
- Use meaningful variable names with proper quoting
- Include error handling and logging

### Docker
- Multi-stage builds when appropriate
- Minimize layer count and image size
- Use specific base image tags (not `latest`)
- Follow security best practices

### Documentation
- Use clear, concise language
- Include practical examples
- Test all code snippets
- Update relevant sections when making changes

### Commit Messages
Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description

[optional body]

[optional footer(s)]
```

**Types:**
- `feat`: New features
- `fix`: Bug fixes
- `docs`: Documentation changes
- `style`: Formatting, missing semicolons, etc.
- `refactor`: Code restructuring without functionality changes
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples:**
```
feat(vpn): add WireGuard support for new providers
fix(healthcheck): improve VPN connectivity detection
docs(readme): update quick start guide with Docker Compose
```

## 🧪 Testing Guidelines

### Manual Testing
1. **VPN Connectivity:**
   ```bash
   # Test different VPN providers
   # Verify IP address changes
   # Check DNS leak prevention
   ```

2. **Container Health:**
   ```bash
   # Test startup/shutdown cycles
   # Verify health checks pass
   # Monitor resource usage
   ```

3. **Feature Testing:**
   ```bash
   # Test new features thoroughly
   # Verify backward compatibility
   # Check edge cases
   ```

### Test Scenarios
- Fresh installation with minimal configuration
- Migration from haugene/transmission-openvpn
- Different VPN providers (OpenVPN and WireGuard)
- Various Docker environments (Linux, macOS, Windows)
- Network edge cases (DNS issues, connection drops)

## 📦 Pull Request Process

### Before Submitting
1. **Test your changes** thoroughly
2. **Update documentation** if needed
3. **Check for breaking changes**
4. **Ensure code follows our standards**
5. **Rebase on latest main** branch

### Pull Request Template
Use our [PR template](.github/pull_request_template.md) and include:
- Clear description of changes
- Testing performed
- Breaking changes (if any)
- Related issues

### Review Process
1. **Automated checks** must pass (GitHub Actions)
2. **Maintainer review** for code quality and functionality
3. **Testing verification** on different environments
4. **Documentation review** for user-facing changes

## 🏗️ Project Structure

```
transmissionvpn/
├── .github/                    # GitHub templates and workflows
├── config/                     # Sample configurations
├── docs/                       # Detailed documentation
├── root/                       # Container initialization scripts
├── scripts/                    # Monitoring and utility scripts
├── Dockerfile                  # Container definition
├── docker-compose.yml          # Docker Compose setup
├── .env.sample                 # Environment configuration template
└── README.md                   # Main documentation
```

### Key Files
- **Dockerfile**: Container build instructions
- **root/vpn-setup.sh**: VPN configuration and startup
- **root/healthcheck.sh**: Container health monitoring
- **scripts/monitor.sh**: External monitoring script
- **scripts/metrics-server.py**: Prometheus metrics endpoint

## 🔒 Security Considerations

### Sensitive Information
- Never commit real VPN credentials
- Use placeholder values in examples
- Be cautious with log output
- Review changes for information disclosure

### Security Reviews
- VPN configuration handling
- Network isolation and kill switch
- File permissions and access
- Container security practices

## 🤝 Community Guidelines

### Code of Conduct
- Be respectful and inclusive
- Focus on constructive feedback
- Help newcomers learn and contribute
- Maintain a welcoming environment

### Communication
- Use GitHub issues for bug reports and feature requests
- Participate in discussions respectfully
- Provide helpful and detailed responses
- Share knowledge and experience

## 📚 Resources

### Documentation
- [Docker Documentation](https://docs.docker.com/)
- [OpenVPN Documentation](https://openvpn.net/community-resources/)
- [WireGuard Documentation](https://www.wireguard.com/quickstart/)
- [LinuxServer.io Documentation](https://docs.linuxserver.io/)

### Tools
- [ShellCheck](https://www.shellcheck.net/) - Shell script analysis
- [Hadolint](https://github.com/hadolint/hadolint) - Dockerfile linting
- [Docker Bench](https://github.com/docker/docker-bench-security) - Security scanning

## 🏷️ Release Process

### Versioning
We follow [Semantic Versioning](https://semver.org/):
- `MAJOR.MINOR.PATCH-BUILD`
- Major: Breaking changes
- Minor: New features (backward compatible)
- Patch: Bug fixes
- Build: Container build number

### Release Checklist
1. Update version in relevant files
2. Update CHANGELOG.md
3. Test release candidate
4. Create GitHub release
5. Trigger Docker Hub build
6. Update documentation

## ❓ Getting Help

- **Questions**: Use [GitHub Discussions](https://github.com/magicalyak/transmissionvpn/discussions)
- **Support**: Use our [support template](.github/ISSUE_TEMPLATE/support.yml)
- **Chat**: Join our community discussions
- **Documentation**: Check our [comprehensive docs](docs/)

## 🙏 Recognition

Contributors are recognized through:
- GitHub contributor graphs
- Release notes acknowledgments
- Community shout-outs
- Maintainer recommendations

Thank you for contributing to TransmissionVPN! Your efforts help make secure torrenting accessible to everyone. 