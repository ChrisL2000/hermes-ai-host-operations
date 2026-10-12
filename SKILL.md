---
name: hermes-ai-host-operations
description: "Rebuild the zeppo Debian AI host: OS, drivers, boot, Docker."
version: 0.1.0
author: ChrisL2000, Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [debian, intel-arc, xe, battlemage, docker, grub, headless, host, rebuild, tailscale]
    related_skills: [intel-xe-gpu-setup, vllm-b70-qwen38-deploy, hermes-vllm-operations-tuning, ai-container-ops]
    category: devops
---

# zeppo AI host — base OS reconstruction

Everything needed to take a blank machine and a Debian 13 (trixie) installer image back to
the host that runs the B70 vLLM brain: partitioning, package sources (backports kernel,
Intel compute runtime from Ubuntu PPAs), Docker, users/groups, the headless GRUB switch and
the Hermes system config. Captured from the live host on 2026-10-12; `scripts/host-snapshot.sh`
re-captures it so the reference never goes stale silently.

## When to Use

- Reinstalling or cloning the host (new disk, new box, disaster recovery)
- "Why does the GPU work on zeppo but not on this other Debian box" (driver stack is the answer)
- Changing boot behaviour (headless vs graphical), kernel, or Docker storage
- Don't use for: container-level work (`ai-container-ops`, `vllm-b70-qwen38-deploy`),
  GPU passthrough troubleshooting inside containers (`intel-xe-gpu-setup`)

## Prerequisites

- Debian 13.x amd64 installer (DVD-1 with firmware or netinst) on USB; UEFI boot
- Hardware as captured: i7-8700K, 64 GB, Intel Arc Pro B70 (PCI 03:00.0, 8086:e223),
  UHD 630 iGPU, NVMe 1.8 TB (system), NVMe 477 GB (NTFS data), 10.9 TB SATA (LVM, Docker spill)
- Network: wired `enp8s0`; Tailscale account for `100.93.126.10` (new node will get a new IP)
- Root/sudo during install; the Hermes provider API key for `/etc/hermes/config.yaml`

## How to Run

```
# capture the current host state (safe, read-only; writes one markdown file)
terminal(command="~/.hermes/skills/devops/hermes-ai-host-operations/scripts/host-snapshot.sh /tmp/zeppo-host-$(date +%F).md")

# apply the post-install layer on a fresh Debian 13 (run as root, idempotent, prints each stage)
terminal(command="sudo ~/.hermes/skills/devops/hermes-ai-host-operations/scripts/post-install.sh", timeout=1800)
```

The installer phase (partitioning, tasksel) is manual; the procedure below says exactly what
to pick. Everything after first boot is `post-install.sh`.

## Quick Reference

| Layer | What zeppo has | Source |
|---|---|---|
| OS | Debian 13 trixie, hostname `zeppo`, `en_US.UTF-8`, tasks: kde-desktop, desktop, ssh-server (+ xfce4, xrdp) | installer |
| Kernel | `linux-image-amd64` 7.1.13 **from trixie-backports** (6.12 stock cannot drive Battlemage) + `firmware-intel-graphics` backports | `assets/apt/` |
| GPU userspace | `intel-opencl-icd libze-intel-gpu1 libze1 intel-ocloc libigdgmm12 libigc2 libigdfcl2 clinfo intel-gpu-tools` from **kobuk-team/intel-graphics** (noble, pin 700) with repositories.intel.com as fallback (pin 600) | `assets/apt/` |
| Driver binding | `xe` auto-binds 8086:e223 (renderD129); `i915` keeps UHD 630 (renderD128). No modules-load/modprobe config needed. | kernel default |
| Docker | docker-ce 29.x from download.docker.com; `data-root /home/docker-data`, overlay2 | `assets/docker/daemon.json` |
| Users | `chrismok` uid 1000 (admin), `zeppo` uid 1001 service account, both in `render` (992) + `docker` (988); sudoers `chrismok-hermes` | `assets/sudoers/` |
| Boot | `headless-switch.service` masks sddm/xrdp + sets multi-user when cmdline has `zeppo.headless`; GRUB 40_custom entry carries that param | `assets/boot/` |
| Disks | nvme1n1: EFI 976M + /boot 977M + LVM `zeppo-vg` {root 93G, var 37G, tmp 2.8G, home 1.7T, swap 32G}; sda: LVM `docker-storage-vg/docker-data` 9.8T ext4 at `/var/lib/docker-storage`; nvme0n1p1 NTFS at `/mnt/gamez` | installer + fstab |
| Extras | tailscale, gh, git-crypt, ufw (enabled), lm-sensors, smartmontools, claude-desktop repo, dkms, build-essential, cmake, ffmpeg, tmux, ripgrep | `post-install.sh` |
| Hermes | per-user installs at `~/.hermes/hermes-agent` (chrismok, zeppo); system scope `/etc/hermes/config.yaml` = provider `vllm-b70-qwen38` @ localhost:8081, context_length 131072 | `assets/hermes/` |

Full captured detail (package lists, fstab, cmdline, units, pins): `references/zeppo-host-config.md`.

## Procedure

1. **Install Debian 13** from the image. Hostname `zeppo`, locale en_US.UTF-8, timezone
   America/New_York. Partition nvme1n1 manually: 976 MB EFI, 977 MB ext4 `/boot`, rest LVM VG
   `zeppo-vg` with LVs root 93G, var 37G, tmp 2.8G, swap 32G, home = remainder. Tasksel:
   Debian desktop, KDE, SSH server. Create user `chrismok` (uid 1000).
   Completion: first boot reaches sddm, `ssh chrismok@zeppo` works.
2. **Run `scripts/post-install.sh`** as root. Stages: apt sources + pins → backports kernel +
   firmware → Intel compute runtime → Docker CE + daemon.json → tools (tailscale, gh,
   git-crypt, ufw, sensors, smartmontools) → users/groups/sudoers → headless switch + GRUB
   entry → secondary disks in fstab → `/etc/hermes/config.yaml` skeleton.
   Completion: script prints `post-install: done`; `reboot` into the backports kernel.
3. **Verify the GPU stack** after reboot: `uname -r` = 7.1.x, `lsmod | grep ^xe`,
   `ls -l /sys/class/drm/renderD*/device/driver` shows one xe + one i915, `clinfo | head`
   lists Intel(R) OpenCL Graphics, `id zeppo` includes render+docker.
   Completion: all four true (see `intel-xe-gpu-setup` if not).
4. **Headless mode**: pick the `Debian GNU/Linux (headless, no display server)` GRUB entry
   (or make it default with `GRUB_DEFAULT="Debian GNU/Linux (headless, no display server)"`
   + `update-grub`). Completion: `systemctl get-default` = multi-user, sddm/xrdp masked,
   `:22` open, `:3389` closed.
5. **Join Tailscale** (`tailscale up`), set `ufw` rules (allow ssh + tailscale0), restore
   `/etc/hermes/config.yaml` API key, install Hermes per user (`hermes-agent` skill), then
   deploy the brain with `vllm-b70-qwen38-deploy`. Completion: `curl localhost:8081/health` = 200.

## Pitfalls

- **Stock trixie kernel 6.12 does not drive the B70** (Battlemage needs xe from 7.1+ plus the
  backports `firmware-intel-graphics`); without backports you get a black card and
  `clinfo: 0 platforms`. Keep `linux-image-amd64` pinned to backports.
- The Intel compute runtime on this host comes from **Ubuntu noble** repos (PPA + Intel). Debian
  has no current Level Zero for Battlemage. The pins in `assets/apt/preferences.d/` make only
  the listed packages come from there; anything else from those origins is priority 100. Do
  not `apt upgrade` with the pins removed.
- `/etc/modprobe.d/intel-microcode-blacklist.conf` blacklists the `microcode` module while
  `intel-microcode` is installed (early-load via initramfs still applies). Keep as captured.
- Docker's data-root is `/home/docker-data` (on the 1.7 TB home LV), **not** the 9.8 TB
  `docker-storage-vg` mounted at `/var/lib/docker-storage` — that volume is mounted but unused.
  Decide deliberately on rebuild; moving data-root later means re-pulling/rebuilding images.
- `headless-switch.service` runs at `basic.target` and *masks* units; booting the normal GRUB
  entry unmasks them again. Never mask sddm by hand — the switch owns that state.
- GPU power cap (`power1_cap`) is **not persisted**; it is the 275 W card default after boot.
- `sudo.service` is masked on zeppo (harmless; the `sudo` binary does not need it).
- `/mnt/gamez` is NTFS via ntfs-3g with uid/gid 1000; if the disk is absent, drop its fstab
  line or boot hangs on the mount.

## Verification

- `scripts/host-snapshot.sh` output diffs cleanly against `references/zeppo-host-config.md`
  apart from timestamps, Tailscale IP and package point-versions.
- Step-3 GPU checks pass; `docker run --rm --device /dev/dri --group-add 992 <xpu image> clinfo`
  sees the B70 from inside a container.
- `vllm-b70-qwen38-deploy/scripts/verify.sh` passes after the brain is deployed.
