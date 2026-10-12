# hermes-ai-host-operations

Rebuild recipe for **zeppo**, a Debian 13 (trixie) host that serves a local LLM on an
**Intel Arc Pro B70** (Battlemage) under Docker — packaged as a
[Hermes Agent](https://hermes-agent.nousresearch.com) skill. Given a Debian 13 installer image
and the same hardware, the procedure here reproduces the base OS: backports kernel + firmware
for the xe driver, Intel Level Zero / OpenCL userspace, Docker CE with a custom data-root,
service accounts and sudo policy, a GRUB "headless" boot entry that masks the display stack,
and the system-wide Hermes provider config.

Companion repos: [vllm-b70-qwen38-deploy](https://github.com/ChrisL2000/vllm-b70-qwen38-deploy)
puts the tuned Qwen3.8-27B vLLM container on top of this host.

## Layout

```
SKILL.md                              procedure, quick reference, pitfalls
references/zeppo-host-config.md       full captured configuration (packages, fstab, units, pins...)
scripts/host-snapshot.sh              re-capture the live host into markdown (read-only)
scripts/post-install.sh               idempotent post-install layer for a fresh Debian 13 (run as root)
assets/apt/                           sources.list(.d), apt pins, signing keys
assets/boot/                          headless-switch.sh + .service, GRUB 40_custom entry, modprobe.d
assets/docker/daemon.json             data-root /home/docker-data, overlay2
assets/sudoers/chrismok-hermes        admin + service-account sudo policy (template)
assets/hermes/config.yaml             /etc/hermes/config.yaml skeleton (API key redacted)
```

## Why this host is unusual

* **Stock trixie kernel 6.12 cannot drive Battlemage.** `linux-image-amd64` 7.1.x and
  `firmware-intel-graphics` come from `trixie-backports`.
* **Debian has no current Level Zero for Battlemage.** The compute runtime
  (`intel-opencl-icd libze-intel-gpu1 libze1 intel-ocloc libigdgmm12 libigc2 libigdfcl2`) is
  installed from the Ubuntu *noble* `kobuk-team/intel-graphics` PPA (apt pin 700) with
  `repositories.intel.com` as fallback (pin 600). Everything else from those origins is pinned
  to 100 so they cannot pull in unrelated Ubuntu packages.
* `xe` binds the B70 (`renderD129`) and `i915` keeps the UHD 630 iGPU (`renderD128`) with no
  modprobe configuration; containers get `/dev/dri` plus `group_add: ["992"]` (the render GID).
* A oneshot `headless-switch.service` reads the kernel cmdline: if `zeppo.headless` is present
  it masks sddm/xrdp and sets `multi-user.target`; the normal GRUB entry restores graphical.

## Usage

```bash
# on the live host: refresh the captured config
scripts/host-snapshot.sh references/zeppo-host-config.md

# on a fresh Debian 13 install (after the manual installer steps in SKILL.md):
sudo scripts/post-install.sh            # or --dry-run; SKIP="tools users" to skip stages
sudo reboot                             # into the 7.1 backports kernel
lsmod | grep ^xe && clinfo | head       # GPU stack check
```

Install as a Hermes skill: `cp -r . ~/.hermes/skills/devops/hermes-ai-host-operations`.

## License

MIT.
