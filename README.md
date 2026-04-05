# DigitalD.tech Personal VPN Panel

DigitalD.tech Personal VPN Panel is a self-hosted VPN management panel for personal use. It helps deploy and manage multiple VPN protocols from one server with a web admin panel, user provisioning, share links, QR export, and one-command installation for modern Linux VPS environments.

This project is not for commercial use.

## Features

- Multi-protocol support from one panel
- Web-based user management and config export
- Share links and QR codes for client onboarding
- One-command installer for fresh servers
- Prebuilt container release flow for faster deployments

## Supported Protocols

- OpenVPN
- WireGuard
- AmneziaWG
- IKEv2
- OpenConnect
- Xray

## Quick Install

```bash
PUBLIC_HOST=178-104-66-85.sslip.io bash -c "$(curl -fsSL https://raw.githubusercontent.com/tnzil/all-in-one-vpn-panel/main/install.sh)"
```

Replace the `PUBLIC_HOST` value with any hostname that resolves to your server (DuckDNS, `sslip.io`, your own domain) and rerun the same command. Nothing else needs to change.

## Supported Architectures

- Linux x86_64 (amd64)
- Linux arm64

Installers download the matching `vpn-panel-linux-<arch>` binary from the latest release assets so both architectures are covered without manual swaps.

## Requirements

- Ubuntu 24.04 or Debian 12
- Root access
- Docker-capable VPS
- `/dev/net/tun` available

## What Gets Published Here

This public repository is the release and distribution entrypoint. It is intended to contain:

- release binaries
- install script
- release notes
- container image references

The source development workflow can remain private while public binaries and images are published from CI.

## Images

Published container images use GitHub Container Registry:

- `ghcr.io/tnzil/all-in-one-vpn-panel-backend`
- `ghcr.io/tnzil/all-in-one-vpn-panel-openvpn`
- `ghcr.io/tnzil/all-in-one-vpn-panel-ikev2`
- `ghcr.io/tnzil/all-in-one-vpn-panel-amneziawg`
- `ghcr.io/tnzil/all-in-one-vpn-panel-openconnect`

## License

This project uses the PolyForm Noncommercial 1.0.0 license.

---

- ⚙️ **DigitalD.tech** (https://digitald.tech) provides commercial VPN solutions and develops apps across Windows, Linux, macOS, Android, and iOS.
- ✅ Panel builds are tested and verified with the TunnelHQ automated checks at https://tunnelhq.com for OpenVPN, WireGuard, IKEv2, OpenConnect, AmneziaWG, and Xray.
- 📦 This project ships personal-use binaries and configs; commercial deployments require a DigitalD.tech agreement.
