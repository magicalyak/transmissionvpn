# Troubleshooting Scripts

Collection of scripts to diagnose and fix common TransmissionVPN monitoring issues.

## 🔧 Scripts

### `quick-network-fix.sh`
**Quick fix for networking issues**
- Connects Prometheus to TransmissionVPN's network
- Tests connectivity between containers
- Fastest solution for most problems

```bash
./quick-network-fix.sh
```

### `fix-prometheus-issues.sh`
**Comprehensive diagnostics**
- Checks container status and configuration
- Verifies metrics endpoints
- Tests Prometheus scraping
- Provides detailed troubleshooting steps

```bash
./fix-prometheus-issues.sh
```

### `fix-networking-issues.sh`
**Advanced network troubleshooting**
- Deep network analysis
- Container IP inspection
- Multiple fix strategies
- Detailed connectivity testing

```bash
./fix-networking-issues.sh
```

## 🚀 Usage

1. **Make scripts executable:**
   ```bash
   chmod +x *.sh
   ```

2. **Start with the quick fix:**
   ```bash
   ./quick-network-fix.sh
   ```

3. **If issues persist, run comprehensive diagnostics:**
   ```bash
   ./fix-prometheus-issues.sh
   ```

## 🎯 Common Issues Fixed

- **DNS resolution failures** between containers
- **Network isolation** problems
- **Missing environment variables**
- **Port connectivity** issues
- **Prometheus configuration** errors 