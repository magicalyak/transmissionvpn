# Versioning Scheme

## Overview
This project follows the **linuxserver.io transmission** versioning scheme with patch increments.

## Format
```
v{TRANSMISSION_VERSION}-r{PATCH_NUMBER}
```

## Components
- **TRANSMISSION_VERSION**: The upstream linuxserver.io transmission version (e.g., `4.0.6`)
- **PATCH_NUMBER**: Incremental patch number starting from 1 (e.g., `r1`, `r2`, `r8`)

## Examples
- `v4.0.6-r1` - First patch release based on transmission 4.0.6
- `v4.0.6-r8` - Eighth patch release based on transmission 4.0.6
- `v4.0.7-r1` - First patch release when transmission updates to 4.0.7

## Release Process
1. **Check Current Version**: `git describe --tags --abbrev=0`
2. **Increment Patch**: Increase the `-rX` number by 1
3. **Create Tag**: `git tag -a v{VERSION} -m "Release v{VERSION}: {DESCRIPTION}"`
4. **Push Changes**: `git push origin main && git push origin v{VERSION}`
5. **Create GitHub Release**: Use GitHub CLI or web interface

## Version History
- `v4.0.6-r23` - Enhanced VPN kill switch with strict iptables rules, DNS leak prevention, and active monitoring
- `v4.0.6-r22` - Enhanced security posture to address Docker Scout findings
- `v4.0.6-r21` - Improved Docker tagging strategy, cleanup stale docs, fix workflow for convenience tags
- `v4.0.6-r20` - DNS fixes and updated dependencies
- `v4.0.6-r19` - Previous release
- `v4.0.6-r18` - Previous release
- `v4.0.6-r17` - Previous release
- `v4.0.6-r16` - Previous release
- `v4.0.6-r15` - Previous release
- `v4.0.6-r14` - Previous release
- `v4.0.6-r13` - Previous release
- `v4.0.6-r12` - Previous release
- `v4.0.6-r11` - Previous release
- `v4.0.6-r10` - Previous release
- `v4.0.6-r9` - Critical kill switch fix: Allow VPN server traffic before applying kill switch
- `v4.0.6-r8` - Fix VPN connection and health check bugs, restructure monitoring
- `v4.0.6-r7` - Previous release
- `v4.0.6-r6` - Previous release
- `v4.0.6-r5` - Previous release

## Important Notes
- **DO NOT** create versions like `v4.0.7` unless linuxserver.io transmission actually releases 4.0.7
- Always check the [linuxserver.io transmission releases](https://github.com/linuxserver/docker-transmission/releases) for the current upstream version
- The base version should match the upstream transmission version exactly
- Only increment the patch number (`-rX`) for our custom fixes and improvements 