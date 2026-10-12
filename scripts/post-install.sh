#!/usr/bin/env bash
# Post-install layer for a fresh Debian 13 (trixie) install, reproducing the zeppo AI host.
# Run as root. Idempotent. Each stage prints its name; set SKIP="stage1 stage2" to skip stages.
#   sudo post-install.sh [--dry-run]
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
A="$here/assets"
dry=0; [[ "${1:-}" == "--dry-run" ]] && dry=1
[[ $EUID -eq 0 || $dry -eq 1 ]] || { echo "run as root (sudo)" >&2; exit 2; }
SKIP="${SKIP:-}"
stage() { printf '\n==> %s\n' "$1"; [[ " $SKIP " == *" $1 "* ]] && { echo "(skipped)"; return 1; }; (( dry )) && { echo "(dry-run)"; return 1; }; return 0; }
install_file() { install -D -m "${3:-0644}" "$1" "$2"; echo "  $2"; }

ADMIN_USER="${ADMIN_USER:-chrismok}"
SERVICE_USER="${SERVICE_USER:-zeppo}"

if stage apt-sources; then
  install_file "$A/apt/sources.list" /etc/apt/sources.list
  for f in "$A"/apt/sources.list.d/*; do install_file "$f" "/etc/apt/sources.list.d/$(basename "$f")"; done
  for f in "$A"/apt/preferences.d/*; do install_file "$f" "/etc/apt/preferences.d/$(basename "$f")"; done
  install_file "$A/apt/keyrings/docker.asc" /etc/apt/keyrings/docker.asc
  install_file "$A/apt/keyrings/githubcli-archive-keyring.gpg" /etc/apt/keyrings/githubcli-archive-keyring.gpg
  install_file "$A/apt/keyrings/intel-graphics.gpg" /usr/share/keyrings/intel-graphics.gpg
  install_file "$A/apt/keyrings/kobuk-intel.gpg" /usr/share/keyrings/kobuk-intel.gpg
  # tailscale keyring is shipped by its own package once the repo is reachable; bootstrap it
  [[ -f /usr/share/keyrings/tailscale-archive-keyring.gpg ]] || curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  apt-get update
fi

if stage kernel-backports; then
  # Battlemage needs xe from kernel 7.1+ and current GuC firmware: both come from trixie-backports
  apt-get install -y -t trixie-backports linux-image-amd64 linux-headers-amd64 firmware-intel-graphics firmware-realtek
  install_file "$A/boot/intel-microcode-blacklist.conf" /etc/modprobe.d/intel-microcode-blacklist.conf
  apt-get install -y intel-microcode
fi

if stage intel-compute-runtime; then
  # Level Zero / OpenCL for Battlemage from the kobuk-team PPA (pin 700) with Intel's repo as fallback (pin 600)
  apt-get install -y intel-opencl-icd libze-intel-gpu1 libze1 intel-ocloc libigdgmm12 libigc2 libigdfcl2 clinfo clpeak intel-gpu-tools libdrm-dev
fi

if stage docker; then
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  install_file "$A/docker/daemon.json" /etc/docker/daemon.json
  mkdir -p /home/docker-data && chmod 711 /home/docker-data
  systemctl enable --now docker
fi

if stage tools; then
  apt-get install -y tailscale gh git git-lfs git-crypt ufw lm-sensors smartmontools dkms build-essential cmake pkg-config \
    python3-dev ffmpeg tmux ripgrep lsof lshw pciutils usbutils ntfs-3g xrdp xorgxrdp xfce4 xfce4-goodies xvfb nftables
  systemctl enable --now tailscaled lm-sensors smartmontools
fi

if stage users; then
  id "$ADMIN_USER" >/dev/null 2>&1 || adduser --disabled-password --gecos '' "$ADMIN_USER"
  id "$SERVICE_USER" >/dev/null 2>&1 || adduser --disabled-password --gecos 'Hermes service account' "$SERVICE_USER"
  getent group render >/dev/null || groupadd -g 992 render
  usermod -aG render,docker,video "$ADMIN_USER"
  usermod -aG render,docker,video "$SERVICE_USER"
  sed "s/chrismok/$ADMIN_USER/g; s#/home/zeppo/#/home/$SERVICE_USER/#g" "$A/sudoers/chrismok-hermes" > /etc/sudoers.d/"$ADMIN_USER"-hermes
  chmod 0440 /etc/sudoers.d/"$ADMIN_USER"-hermes && visudo -cf /etc/sudoers.d/"$ADMIN_USER"-hermes
  echo "  render gid now: $(getent group render | cut -d: -f3) (vLLM compose group_add must match)"
fi

if stage headless-boot; then
  install_file "$A/boot/headless-switch.sh" /usr/local/sbin/headless-switch.sh 0755
  install_file "$A/boot/headless-switch.service" /etc/systemd/system/headless-switch.service
  systemctl daemon-reload && systemctl enable headless-switch.service
  if ! grep -q 'Zeppo headless entry' /etc/grub.d/40_custom; then
    kver="$(ls /boot/vmlinuz-7.* 2>/dev/null | sed 's#.*/vmlinuz-##' | sort -V | tail -1)"
    boot_uuid="$(findmnt -no UUID /boot)"
    root_dev="$(findmnt -no SOURCE /)"
    sed -e "s#7.1.13+deb13-amd64#${kver:-7.1.13+deb13-amd64}#g" -e "s#de13387d-0883-4ac8-be25-de2781836fc9#$boot_uuid#" \
        -e "s#/dev/mapper/zeppo--vg-root#$root_dev#" "$A/boot/40_custom-headless-entry" >> /etc/grub.d/40_custom
    update-grub
  else echo "  GRUB entry already present"; fi
fi

if stage hermes-system-config; then
  [[ -f /etc/hermes/config.yaml ]] || install_file "$A/hermes/config.yaml" /etc/hermes/config.yaml
  echo "  edit /etc/hermes/config.yaml: replace api_key CHANGEME"
fi

echo; echo "post-install: done. Reboot into the backports kernel, then verify: uname -r; lsmod | grep ^xe; clinfo | head"
echo "Manual follow-ups: tailscale up; ufw allow ssh && ufw allow in on tailscale0 && ufw enable; secondary disks in /etc/fstab (see references/zeppo-host-config.md)"
