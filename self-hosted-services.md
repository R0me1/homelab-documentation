# Self-Hosted Services

Privacy-first replacements for mainstream cloud services, running on my own infrastructure and reachable only over an encrypted **WireGuard VPN** — nothing is exposed to the public internet.

## Why self-host

Two reasons: **data ownership** — my files and photos live on hardware I control, not a third party's servers — and **hands-on practice** with the Linux, Docker, networking and storage skills that underpin IT and security work.

## Immich — private photo & video backup (replaced iCloud)

[Immich](https://immich.app) is a self-hosted photo and video platform that I migrated to from iCloud. It backs up photos and videos from my phone automatically in the background, with machine-learning search and face grouping — the features people expect from iCloud or Google Photos — but with everything stored on hardware I own. Runs in Docker, with photo and video data held on my NAS.

## Nextcloud — personal cloud (files, sync & sharing)

[Nextcloud](https://nextcloud.com) is my self-hosted alternative to Google Drive and Dropbox: file storage, sync across devices, sharing, and calendar/contacts. Files are backed by NAS storage, so capacity is mine to expand rather than a monthly subscription tier.

## WireGuard — secure remote access

This is the part I'm most deliberate about. Rather than port-forwarding each service to the open internet — which means an exposed login page for every app and a constant stream of automated attacks against it — **none of these services are publicly reachable.** Instead I connect into my home network through an encrypted **WireGuard** tunnel and reach everything internally, exactly as if I were sitting at home.

The payoff is a much smaller attack surface: a single modern, hardened entry point instead of many exposed services. It's the same principle a corporate VPN applies, implemented at home.

## Infrastructure

These run on a homelab built around:

- **Proxmox** — virtualisation host for VMs and containers
- **Docker** — containerised service deployment
- **TrueNAS** — storage for files, photos and backups
- **UniFi** — network with VLAN segmentation and firewall rules
- internal **DNS** for name resolution across services

## What this demonstrates

Linux administration, Docker and containers, networking and DNS, VPN configuration, storage management — and, most importantly, a **security- and privacy-first architecture**: keep services private, expose the minimum, and reach them over an encrypted tunnel.
