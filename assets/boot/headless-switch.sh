#!/bin/sh
# headless-switch.sh — boot-time switch for the display stack.
#
# Reads the kernel command line (default: /proc/cmdline, overridable via
# $2 for testing). If it contains "zeppo.headless", the display stack
# (sddm, xrdp, xrdp-sesman) is masked and the default target set to
# multi-user.target. Otherwise it is unmasked and the default target
# restored to graphical.target.
#
# Idempotent: safe to run repeatedly. No packages are installed or removed.
# Rollback is simply booting the normal menu entry (no shell required).

set -e

CMDLINE_FILE="${2:-/proc/cmdline}"
SERVICES="sddm.service xrdp.service xrdp-sesman.service"

CMDLINE="$(tr ' ' '\n' < "$CMDLINE_FILE")"

if [ "${1:-}" = "--dry-run" ]; then
    echo "[dry-run] cmdline file: $CMDLINE_FILE"
    case "$CMDLINE" in
        *"zeppo.headless"*)
            echo "[dry-run] HEADLESS branch: would mask $SERVICES"
            echo "[dry-run] HEADLESS branch: would set default target to multi-user.target"
            ;;
        *)
            echo "[dry-run] GRAPHICAL branch: would unmask $SERVICES"
            echo "[dry-run] GRAPHICAL branch: would set default target to graphical.target"
            ;;
    esac
    exit 0
fi

case "$CMDLINE" in
    *"zeppo.headless"*)
        echo "headless-switch: headless boot requested; masking display stack"
        systemctl mask $SERVICES
        systemctl set-default multi-user.target
        echo "headless-switch: headless mode active (default=multi-user, sddm/xrdp masked)"
        ;;
    *)
        echo "headless-switch: graphical boot; restoring display stack"
        systemctl unmask $SERVICES
        systemctl set-default graphical.target
        echo "headless-switch: graphical mode active (default=graphical, display stack unmasked)"
        ;;
esac
