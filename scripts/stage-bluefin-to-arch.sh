#!/bin/bash
# Stage an Arch bootc deployment without formatting, repartitioning, or rebooting.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_REF="${1:-ttl.sh/oci-native/archlinux:latest}"
TARGET_USER="${BOOTC_USER:-bupd}"
BACKUP_ROOT="/var/home/${TARGET_USER}/arch-switch-backups"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0 [image-ref]" >&2
    exit 1
fi

"${SCRIPT_DIR}/validate-bluefin-switch.sh"

echo
echo "This stages an in-place bootc switch to:"
echo "  ${IMAGE_REF}"
echo
echo "It does not format the NVMe, recreate LUKS, change filesystem labels, or reboot."
echo "The booted Bluefin deployment remains available as the bootc rollback."
read -r -p "Type 'stage arch' to continue: " confirmation
[ "$confirmation" = "stage arch" ] || {
    echo "Aborted."
    exit 1
}

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="${BACKUP_ROOT}/${stamp}"
install -d -m 0700 -o "$TARGET_USER" -g "$TARGET_USER" "$backup_dir"

bootc status --format=json > "${backup_dir}/bootc-status-before.json"
bootctl status > "${backup_dir}/bootctl-status-before.txt"
lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL,UUID,PARTUUID,MOUNTPOINTS \
    > "${backup_dir}/lsblk-before.txt"
cp /proc/cmdline "${backup_dir}/kernel-cmdline-before.txt"
cryptsetup status root > "${backup_dir}/cryptsetup-root-before.txt"
printf 'image=%s\n' "$IMAGE_REF" > "${backup_dir}/image-target.txt"
chown -R "$TARGET_USER:$TARGET_USER" "$backup_dir"

echo
echo "Saved recovery metadata under ${backup_dir}"
echo "Staging the Arch deployment. This command does not reboot."
bootc switch "$IMAGE_REF"

echo
echo "Staged deployment:"
bootc status
echo "Do not reboot until the staged deployment has also been tested in a VM."
echo "Bluefin remains the rollback deployment."
