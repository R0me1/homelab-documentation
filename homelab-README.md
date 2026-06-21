<div align="center">

# Home Lab & Documentation

Documentation from my self-built home lab, which I use to practise IT support and security tasks hands-on. Each project is written up the way I'd document it on a real service desk: the goal or problem, what I did, and what I learned.

<img src="homelab-rack.jpg" alt="Home lab, 10-inch rack with UniFi gateway, mini-PC nodes and a NAS" width="400">

</div>

---

## Projects

### 🌐 [Home Network & Security Architecture](network-architecture.md)
A segmented, monitored home network with inline Suricata IPS ahead of the gateway, forced recursive DNS on every VLAN, a zone-based default-deny firewall, and a Security Onion SIEM. Includes the full hardware inventory and a network diagram.

### 🔍 [Investigation, Catching Devices That Bypass My DNS](dns-bypass-investigation.md)
DNS query logs turned up a smart TV phoning home every few minutes and a streaming box ignoring the local resolver entirely with hardcoded public DNS. Tracing how devices slipped past my DNS, fixing a resolver SERVFAIL it surfaced, and forcing every device back through the local resolver so logging and blocking actually hold.

### 🖥️ [Active Directory Lab, Tiered "Fakelab Inc." Domain](active-directory-lab.md)
A Windows Server 2025 domain built on Microsoft's tiered administration model and provisioned by an idempotent PowerShell script. Realistic Level 1 to 3 helpdesk practice, NTFS-permissioned file shares, mapped to NIST guidance.

### 🔨 [Hardware: Builds, Upgrades & Repairs](hardware-builds.md)
Machines I've built, upgraded or repaired, including reviving a decommissioned enterprise PC into a Proxmox node and a compact mini-ITX build that hosts a self-hosted LLM.

### 🔧 [Incident Writeup, Thermal NVMe Failure on a Home SIEM](siem-thermal-incident.md)
A misleading "database corrupt" error traced three layers down to an overheating NVMe drive dropping off the PCIe bus. Root-cause analysis under a misleading symptom, safe recovery, and a permanent hardware fix.

### ☁️ [Self-Hosted Services](self-hosted-services.md)
Private, self-hosted Nextcloud and Immich (replacing iCloud), reachable only over an encrypted WireGuard VPN, with no services exposed to the public internet.

---

> **A note on privacy:** company, user and host names in these write-ups are fictional or generalised, and real IP ranges, subnets and SSIDs are intentionally omitted.
