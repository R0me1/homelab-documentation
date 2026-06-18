# Incident Writeup: Diagnosing a Thermal NVMe Failure on a Home SIEM

**Author:** Romel Dawson
**Role:** Home lab owner (self-managed)
**System:** Security Onion 3.1.0 (standalone) on a fanless CWWK mini PC
**Date of incident:** May 2026 (recurring over several days during a heatwave)

---

## Summary

A login failure on my Security Onion SIEM presented as a database corruption error. By following the evidence down the stack rather than treating the error at face value, I established that the "corrupt database" was not the cause but a symptom: the NVMe drive holding the SIEM's data volume had dropped off the PCIe bus after overheating, which forced the filesystem to shut down mid-write and left a database file torn.

The root cause was environmental, a passively cooled (fanless) mini PC running a write-heavy 24/7 workload during a heatwave, with no way to shed heat fast enough. The drive itself was healthy (4% wear, all spare capacity intact); it had simply hit its critical temperature and protected itself by going offline.

I recovered the system by cooling and power-cycling the hardware, repairing the storage layer, restarting the application stack, and resolving a secondary authentication fault that the outage exposed. I then identified a permanent hardware fix to stop the failure recurring.

This writeup walks through the diagnosis because the *method*, separating symptom from cause, and confirming each hypothesis with evidence before acting, is the part worth showing.

---

## Environment

| Component | Detail |
|---|---|
| Platform | CWWK fanless mini PC (aluminium case as passive heatsink) |
| CPU | AMD Ryzen 5 5500U |
| Memory | 32 GB DDR4 |
| OS / boot drive | `nvme0n1`, 119 GB, root, boot, swap (healthy throughout) |
| SIEM data drive | `nvme1n1`, 2 TB Crucial T500, LVM volume `nsm-nsm` mounted at `/nsm` |
| Application | Security Onion 3.1.0, containerised (Docker): Elasticsearch, Logstash, Suricata, Zeek, Kibana, SOC web console, Ory Kratos (auth), and others |
| Access | Web console at `https://<host>/`, plus SSH |

A key piece of context: on this system **`/nsm` holds almost everything that matters**, the search indices, captured logs, and the authentication database. The OS lives on a separate, healthy disk. That separation is what allowed me to keep diagnosing over SSH while the data volume was effectively dead.

---

## The initial symptom

The web login page, which should render a form, instead returned a raw 500 error:

```json
{"error":{"code":500,"status":"Internal Server Error",
"message":"sqlite create: named insert: database disk image is malformed"}}
```

The obvious reading is "a database is corrupt." That reading is correct but unhelpful, because it says nothing about *why* a database that was fine yesterday is malformed today. SQLite's "database disk image is malformed" is very often a downstream symptom of a storage problem rather than an application bug, so I treated it as a starting point, not a conclusion.

---

## Investigation

### Step 1, Identify what's actually serving the page and where the file lives

I confirmed the login path belonged to Ory Kratos (the authentication service Security Onion embeds) and located its SQLite database. The Kratos container's configuration showed:

```
DSN=sqlite:///kratos-data/db.sqlite
/nsm/kratos/db  ->  /kratos-data   (host path : container mount)
```

So the "malformed" file lived at `/nsm/kratos/db/db.sqlite`, on the `/nsm` data volume. That immediately reframed the problem: if other things on `/nsm` were also unhappy, this wasn't an application fault.

### Step 2, Check the storage layer before touching the database

Before running any database repair (which can turn a recoverable file into an unrecoverable one if the underlying storage is failing), I checked the kernel logs and disk health. This is where the real fault appeared:

```
XFS (dm-2): log I/O error -121
XFS (dm-2): Log I/O Error (0x2) ... Shutting down filesystem.
XFS (dm-2): Please unmount the filesystem and rectify the problem(s)
```

The filesystem on `dm-2` had taken an I/O error from the underlying device and **shut itself down to prevent further damage**, correct, protective behaviour. `dm-2` mapped to `nsm-nsm`, i.e. `/nsm`, sitting on the physical disk `nvme1n1`. The database error was a side effect of this shutdown catching a file mid-write.

### Step 3, Establish whether the disk was failing or had simply dropped

The deeper kernel log entries told the real story:

```
nvme1n1: ... Namespace Not Ready (sct 0x0 / sc 0x82)
blk_update_request: critical target error, dev nvme1n1 ...
nvme nvme1: controller is down; will reset: CSTS=0xffffffff, PCI_STATUS=0xffff
nvme nvme1: Removing after probe failure status: -19
nvme1n1: detected capacity change from 3907029168 to 0
```

Reading these in sequence:

- **`Namespace Not Ready`**: the SSD's own controller began rejecting writes.
- **`controller is down ... CSTS=0xffffffff, PCI_STATUS=0xffff`**: the all-ones pattern you get when a PCIe device stops responding entirely; the kernel reads the controller's status register and gets back "nothing there."
- **`Removing after probe failure status: -19`** (`-ENODEV`), the reset failed; there was no device to reset.
- **`capacity change ... to 0`**: the disk node was removed; the device no longer existed.

After this, the drive was gone from the system entirely, `lsblk` no longer listed it, and any command targeting it returned *No such file or directory*. This was not a corrupt database and not a corrupt filesystem; it was a **storage device that had electrically disappeared.**

### Step 4, Rule out the obvious alternatives

I confirmed the failure was isolated to the data drive and its cause, not the wider system:

- **Swap?** No, swap lives on `nvme0n1` (the healthy OS disk), a physically separate device. The two don't interact.
- **Worn-out SSD?** This was the critical question, since the recovery path differs completely for a dying drive versus a transient fault. I couldn't read SMART while the device was absent, so this had to wait until it was back, but the abrupt "fine, then all-ones, then gone" profile pointed at a controller event (recoverable) rather than gradual flash wear-out (terminal).

### Step 5, Identify the real root cause: heat

The deciding clues were physical. The mini PC was too hot to touch, "I've never felt it this hot", and it was a **fanless** chassis (the aluminium case is the only heatsink) during a **heatwave**, with the room noticeably warmer than usual. NVMe SSDs have built-in thermal protection: past a critical temperature, the controller takes itself offline to protect the flash. That presents to the OS exactly as observed, `Namespace Not Ready`, then controller down, then de-enumeration.

The timeline fit a thermal cause rather than a hardware death: the drive limped in a half-failed state for roughly 20 hours (throttling and recovering as the room heated through the day) before the controller finally dropped completely. A drive dying electrically tends to go fast; one slowly cooking degrades over hours exactly like this.

**Root cause:** the NVMe data drive crossed its critical temperature and protected itself by going offline. The filesystem shut down to avoid corruption, and the authentication database, being written at that moment, was left torn, surfacing as the original login error.

---

## Recovery

### 1. Cool and power-cycle the hardware (not a warm reboot)

A warm `reboot` was insufficient and predictably so: it re-runs the same PCIe enumeration that just failed, so a wedged controller stays wedged. I confirmed this, after a warm reboot the drive was still absent, with no new errors because there was no device left to error.

The fix was a **full cold power cycle**: shut down, remove power, let the chassis physically cool (20-30 minutes, longer than it feels necessary because a sealed case stays hot inside), then power on. This lets the drive's controller lose power entirely and cold-boot its own firmware.

After cooling, the drive re-enumerated cleanly:

```
nvme nvme1: pci function 0000:06:00.0
nvme nvme1: 16/0/0 default/read/poll queues
nvme1n1: p1
```

`lsblk` showed `nvme1n1`, the `nsm-nsm` LVM volume, and `/nsm` back. The fact that it returned after cooling was strong confirmation of the thermal theory, dead flash does not come back.

### 2. Repair / verify the storage layer

Because XFS had shut down dirty, the filesystem needed its journal replayed before use. On a clean re-mount XFS replayed automatically; where a manual check was needed the tooling was `xfs_repair` against the LVM device, but importantly, **only with the volume unmounted**, never against a live filesystem.

### 3. Confirm the drive was actually healthy (SMART)

Once the device was back I could finally read its health, which confirmed the drive was fine and the cause was purely environmental:

```
critical_warning                     : 0
available_spare                      : 100%   (threshold 5%)
percentage_used                      : 4%
Warning Temperature Time             : 11
Critical Composite Temperature Time  : 2
temperature                          : ~58 °C
```

The two numbers that matter:

- **`percentage_used: 4%` and `available_spare: 100%`**: the flash is essentially new. This was never a worn-out drive.
- **`Critical Composite Temperature Time: 2`**: the smoking gun. The drive had logged time spent above its *critical* temperature. That is the thermal-cutout fingerprint: it cooked, hit its limit, and protected itself.

### 4. Bring the application stack back up

With healthy storage underneath it, I reconciled the Security Onion stack (`salt-call state.highstate` / `so-status`) and confirmed all containers healthy:

```
✔ This onion is ready to make your adversaries cry!
```

Elasticsearch returned to a green cluster with all shards active, and data ingestion resumed.

---

## Secondary issue: authentication after recovery

After the storage recovery, the login page worked but every data-driven view in the console (Alerts, Hunt, Dashboards, Cases) returned a 500. The backend services were healthy, Elasticsearch green, the SOC web service answering on its port, login working, which meant the failure was narrower than it looked.

Rather than guessing, I followed the request through the stack (browser → nginx reverse proxy → SOC backend → Elasticsearch) and captured the actual error from the SOC log at the moment of failure:

```
security_exception: action [indices:data/read/search] is unauthorized for user
[so_elastic] with effective roles [superuser], because user [so_elastic] is
unauthorized to run as [<my-user>]   ...  "status" : 403
```

This was an Elasticsearch **"run-as" (impersonation) authorisation** failure. The SOC console runs each query as the logged-in user, via the `so_elastic` service account. My user account's run-as mapping had been left in an inconsistent state, so Elasticsearch refused the impersonation, which is why login (a separate system) worked but every *query* failed.

I confirmed the documented resolution in the vendor's own issue tracker for this exact error, then applied it: create a fresh console user (which gets a clean role mapping), verify it can query, and remove the broken account. The query views came straight back.

The transferable lesson here: when login works but everything *behind* it fails, suspect authorisation/identity rather than the data layer, and prove it by reading the error at the point of failure rather than inferring.

---

## Recurrence and confirmation

The failure recurred over subsequent days as the heatwave continued, the same thermal shutdown, the same cold-cycle recovery. Each recovery, the SMART thermal counter ticked up slightly (`Critical Composite Temperature Time` 2 → 3) while wear stayed flat at 4%. This pattern confirmed the diagnosis beyond doubt: a healthy drive being repeatedly driven past its thermal limit by the environment, not a failing component.

That distinction matters, because it points the fix at *cooling*, not at replacing parts.

---

## Permanent remediation

The fanless chassis was the wrong match for a write-heavy 24/7 SIEM workload in a warm room: it has no way to actively shed heat, so on hot days the drive cooks. The fixes, in order of impact:

1. **Add an internal fan.** The board exposes temperature-controlled 4-pin fan headers (these CWWK boards are designed to drive a fan; "fanless" is just the default configuration). Fitting a small fan converts the unit from passive to active cooling and gives the trapped heat somewhere to go, the root-cause fix.
2. **Re-paste the CPU thermal interface.** The factory paste on these units is commonly poor; redoing it is reported to drop temperatures by up to ~20 °C, which materially improves the passive cooling path the whole design depends on.
3. **Couple the NVMe to the chassis.** A thin thermal pad bridging the drive to the metal case (rather than a tall standalone heatsink that just radiates into sealed, still air) lets the case carry the drive's heat away.
4. **BIOS power limits** (lower sustained package power / disable CPU boost) as supporting measures, these reduce heat *generation* but cannot substitute for the cooling above, because the bottleneck was always heat *removal* from a sealed case.

Interim mitigation while sourcing parts: keep an external fan on the unit permanently (not only during incidents), and site the box in the coolest, most open-air location available.

---

## Appendix: key commands used

```bash
# What's listening / running, and where the SQLite files live
sudo ss -tlnp
ps aux | grep -iE 'kratos|auth'
sudo find /var /opt /nsm -type f \( -name '*.sqlite' -o -name '*.db' \)

# Storage and kernel evidence
df -h
sudo dmesg -T | grep -iE 'nvme|xfs|i/o error|controller is down|Namespace Not Ready'
lsblk
sudo dmsetup ls --tree

# Drive health (once re-enumerated)
sudo nvme smart-log /dev/nvme1n1

# Filesystem repair (UNMOUNTED only)
sudo umount /nsm
sudo xfs_repair /dev/mapper/nsm-nsm
sudo mount /nsm

# Application stack
sudo salt-call state.highstate
sudo so-status

# Secondary issue — capturing the real error
sudo tail -f /opt/so/log/soc/sensoroni-server.log   # observed at moment of failure
sudo so-elasticsearch-query _cluster/health?pretty   # confirmed cluster green
```

*Note: hostnames, internal IPs, and user identifiers have been redacted/generalised for publication.*
