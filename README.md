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
curl -fsSL https://raw.githubusercontent.com/tnzil/all-in-one-vpn-panel/main/install.sh -o install.sh
chmod +x install.sh
PUBLIC_HOST=your-domain.example ./install.sh
```

For quick testing, a hostname such as `sslip.io` can be used for the trusted certificate path.

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
