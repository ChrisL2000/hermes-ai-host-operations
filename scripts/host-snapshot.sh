#!/usr/bin/env bash
# Capture the host configuration relevant to rebuilding an Intel-Arc AI host into one markdown file.
# Read-only. Items needing root are attempted with `sudo -n` and marked "(needs sudo)" if refused.
#   host-snapshot.sh [output.md]      (default: stdout)
set -uo pipefail
out="${1:-/dev/stdout}"
exec >"$out"

sec() { printf '\n## %s\n\n```\n' "$1"; }
end() { printf '```\n'; }
run() { "$@" 2>&1 || echo "(failed: $*)"; }
sudo_cat() { sudo -n cat "$1" 2>/dev/null || echo "(needs sudo) $1"; }

echo "# Host snapshot: $(hostname) — $(date -Is)"

sec "Identity"; run hostnamectl; echo; grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release; cat /etc/default/locale 2>/dev/null; readlink /etc/localtime; end
sec "Kernel and boot"; uname -r; cat /proc/cmdline; echo; grep -vE '^#|^$' /etc/default/grub; echo "--- 40_custom"; sed -n '/^[^#]/p' /etc/grub.d/40_custom | grep -v 'exec tail'; echo "--- default target: $(systemctl get-default 2>/dev/null)"; end
sec "Hardware"; run lscpu | grep -E 'Model name|^CPU\(s\)'; free -g | sed -n 2p; lspci -nn | grep -iE 'vga|display|3d'; ls -l /sys/class/drm/renderD*/device/driver 2>/dev/null | sed 's#.*/\(renderD[0-9]*\)/device/driver -> .*/\(.*\)#\1 -> \2#'; for f in /sys/bus/pci/devices/0000:03:00.0/hwmon/hwmon*/power1_cap; do [ -e "$f" ] && echo "power1_cap=$(cat "$f")"; done; end
sec "Modules"; lsmod | grep -E '^(xe|i915) '; echo "--- modules-load.d"; grep -vhE '^#|^$' /etc/modules-load.d/*.conf 2>/dev/null; echo "--- modprobe.d"; grep -rvE '^#|^$' /etc/modprobe.d/ 2>/dev/null; end
sec "Storage"; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | grep -v loop; echo "--- fstab"; grep -vE '^#|^$' /etc/fstab; echo "--- lvm"; run sudo -n lvs --noheadings 2>/dev/null || echo "(needs sudo) lvs"; end
sec "APT sources"; grep -vE '^#|^$' /etc/apt/sources.list; for f in /etc/apt/sources.list.d/*; do echo "--- $f"; grep -vE '^#|^$' "$f"; done; echo "--- preferences.d"; for f in /etc/apt/preferences.d/*; do echo "--- $f"; grep -vE '^#|^$' "$f"; done; end
sec "Packages: manually installed"; apt-mark showmanual | tr '\n' ' '; echo; end
sec "Packages: from backports"; apt list --installed 2>/dev/null | grep -E 'bpo' | cut -d/ -f1 | tr '\n' ' '; echo; end
sec "Packages: from Intel/PPA (Ubuntu noble)"; apt list --installed 2>/dev/null | grep -E 'ppa1|~24\.04' | cut -d/ -f1,2 | tr '\n' ' '; echo; end
sec "Packages: key versions"; dpkg-query -W -f='${Package} ${Version}\n' linux-image-amd64 firmware-intel-graphics intel-opencl-icd libze-intel-gpu1 libze1 docker-ce docker-compose-plugin tailscale gh git-crypt 2>/dev/null; end
sec "Docker"; cat /etc/docker/daemon.json 2>/dev/null; docker version --format 'server {{.Server.Version}}' 2>/dev/null; docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null; echo "--- restart policies"; for c in $(docker ps -aq 2>/dev/null); do docker inspect "$c" --format '{{.Name}} {{.HostConfig.RestartPolicy.Name}}'; done; docker volume ls --format '{{.Name}}' 2>/dev/null | tr '\n' ' '; echo; end
sec "Users and groups"; getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1":"$3":"$4":"$6}'; getent group render docker video sudo; echo "--- sudoers.d"; ls /etc/sudoers.d/; sudo -n -l 2>/dev/null | tail -3; end
sec "systemd: enabled units (non-default)"; systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | awk '{print $1}' | grep -vE '@|getty|systemd-|dbus|cron|rsyslog|apparmor|e2scrub|fstrim|apt-daily|dpkg|ModemManager|NetworkManager|wpa|avahi|cups|bluetooth|anacron|logrotate|man-db|plymouth|remote-fs|ssh|xdg|rtkit|upower|udisks|polkit|accounts|colord|power-profiles|switcheroo|wsdd|unattended' | tr '\n' ' '; echo; echo "--- masked"; systemctl list-unit-files --state=masked --no-legend 2>/dev/null | awk '{print $1}' | tr '\n' ' '; echo; echo "--- custom units"; ls /etc/systemd/system/*.service 2>/dev/null; end
sec "Network"; ip -br a | grep -vE 'veth|br-|docker0|lo '; tailscale ip -4 2>/dev/null; echo "--- ufw"; sudo -n ufw status 2>/dev/null || echo "(needs sudo) ufw status"; echo "--- sshd_config.d"; ls /etc/ssh/sshd_config.d/ 2>/dev/null; end
sec "Hermes"; sed 's/api_key:.*/api_key: <redacted>/' /etc/hermes/config.yaml 2>/dev/null; ls -d /home/*/.hermes/hermes-agent 2>/dev/null; end
