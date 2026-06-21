# Self-Hosted Services

Privacy-first replacements for mainstream cloud services, running on my own infrastructure and reachable only over an encrypted WireGuard VPN, with nothing exposed to the public internet.

## Why self-host

Two reasons. Data ownership: my files and photos live on hardware I control, not a third party's servers. And hands-on practice with the Linux, Docker, networking and storage skills that underpin IT and security work.

## Immich (private photo and video backup, replaced iCloud)

[Immich](https://immich.app) is a self-hosted photo and video platform that I moved to from iCloud. It backs up photos and videos from my phone automatically in the background, with machine-learning search and face grouping (the features people expect from iCloud or Google Photos), but with everything stored on hardware I own. It runs in Docker, with the photo and video data held on my NAS.

## Nextcloud (personal cloud: files, sync and sharing)

[Nextcloud](https://nextcloud.com) is my self-hosted alternative to Google Drive and Dropbox: file storage, sync across devices, sharing, and calendar and contacts. Files are backed by NAS storage, so capacity is mine to expand rather than a monthly subscription tier.

## WireGuard (secure remote access)

Rather than port-forwarding each service to the open internet, which would mean an exposed login page for every app and a constant stream of automated attacks against it, none of these services are publicly reachable. Instead I connect into my home network through an encrypted WireGuard tunnel and reach everything internally, as if I were sitting at home. That keeps the attack surface down to a single hardened entry point instead of many exposed services. It is the same approach a corporate VPN takes, run at home.

I originally used Tailscale for remote access, but moved to self-hosted WireGuard to keep a third party out of the trust path entirely. Access is also scoped per service rather than all-or-nothing: Jellyfin, my media server, is shared with family, while Immich, Navidrome and Nextcloud stay private to me.

## Infrastructure

These run on a homelab built around:

- Proxmox: virtualisation host for VMs and containers
- Docker: containerised service deployment
- TrueNAS: storage for files, photos and backups
- UniFi: network with VLAN segmentation and firewall rules
- internal DNS for name resolution across services
