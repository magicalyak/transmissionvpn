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
- `test`: Add or update tests
- `chore`: Maintenance tasks
- `ci`: CI/CD improvements

**Examples:**

```
feat(vpn): add WireGuard support for new providers
fix(healthcheck): improve VPN connectivity detection
docs(readme): update quick start guide with Docker Compose
```

## 🧪 Testing Guidelines

### Manual Testing

Before submitting, manually test your changes to ensure they work as expected.

1. **VPN Connectivity:**

    ```bash
    docker-compose up -d
    docker-compose logs -f | grep "VPN is connected"
    ```

2. **IP Address Check:**

    ```bash
    docker-compose exec transmissionvpn curl -s https://ipinfo.io/ip
    ```

3. **Application Functionality:**

    - Access the Transmission UI at `http://localhost:9091`.
    - Add a torrent and verify it downloads correctly.

4. **Cleanup:**

    ```bash
    docker-compose down
    ```

### Test Scenarios

- Fresh installation with minimal configuration.
- Upgrading from a previous version.
- All supported VPN providers (if applicable).
- Both OpenVPN and WireGuard connections.
- Sonarr/Radarr integration.
- Alternative web UI functionality.

### Before Submitting

1. **Test your changes** thoroughly.
2. **Update documentation** if you've added or changed functionality.
3. **Follow the coding style** and linting rules.
4. **Write a clear pull request** description.

### Pull Request Template

- Clear description of changes
- Link to the relevant issue (if any)
- Summary of testing performed
- Any necessary follow-up actions

### Review Process

1. **Automated checks** must pass (linting, tests, etc.).
2. **At least one maintainer** will review your PR.
3. **Address any feedback** or requested changes.
4. **Once approved**, your PR will be merged.

## Style Guide

```text
Style guides and best practices for this project.
```

### Key Files

- **Dockerfile**: Container build definition.
- **docker-compose.yml**: Local development and testing.
- **.github/workflows**: CI/CD pipelines.
- **root/**: S6-overlay services and scripts.
- **scripts/**: Helper scripts.
- **docs/**: Project documentation.

### Sensitive Information

- Never commit real VPN credentials, passwords, or API keys.
- Use environment variables or Docker secrets for sensitive data.
- Sanitize logs and command output before sharing.

### Security Reviews

- VPN configuration handling
- Kill switch implementation
- Firewall rules
- Web UI authentication
- Dependency scanning

### Code of Conduct

- Be respectful and inclusive.
- Provide constructive feedback.
- Report any inappropriate behavior.
- See the full [Code of Conduct](./CODE_OF_CONDUCT.md).

### Communication

- Use GitHub issues for bug reports and feature requests.
- Use GitHub discussions for questions and general conversation.
- Join our Discord server for real-time chat.

### Documentation Style

- [Docker Documentation](https://docs.docker.com/get-started/overview/)
- [OpenVPN Documentation](https://openvpn.net/community-resources/reference-manual-for-openvpn-2-4/)
- [WireGuard Documentation](https://www.wireguard.com/documentation/)
- [Transmission Documentation](https://transmissionbt.com/about/)

### Tools

- [ShellCheck](https://www.shellcheck.net/)
- [Hadolint](https://github.com/hadolint/hadolint)
- [markdownlint](https://github.com/DavidAnson/markdownlint)

### Versioning

Follow `MAJOR.MINOR.PATCH-BUILD`.

- `MAJOR`: Breaking changes.
- `MINOR`: New features.
- `PATCH`: Bug fixes.
- `BUILD`: Docker image build number.

### Release Checklist

1. Update version in relevant files.
2. Run all tests and checks.
3. Draft release notes.
4. Create a Git tag.
5. Publish the release.
6. Announce on relevant channels.

## Attribution

- Code contributions are recognized in release notes.
- GitHub contributor graphs.
- Special thanks in the README for significant contributions.

Thank you for contributing! Your support helps make this project better for everyone.
 