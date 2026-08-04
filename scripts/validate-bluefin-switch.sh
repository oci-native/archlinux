#!/bin/bash
# Read-only preflight for switching the installed Bluefin composefs deployment.
set -euo pipefail

readonly TARGET_USER="${BOOTC_USER:-bupd}"
readonly ROOT_MAPPER="${BOOTC_ROOT_MAPPER:-/dev/mapper/root}"
readonly MIN_FREE_GIB="${BOOTC_MIN_FREE_GIB:-15}"
fail=0

check() {
    local label="$1"
    shift

    if "$@"; then
        echo "ok - $label"
    else
        echo "not ok - $label"
        fail=1
    fi
}

root_is_btrfs() {
    [ "$(findmnt -T /sysroot -no FSTYPE)" = "btrfs" ]
}

root_uses_expected_mapper() {
    [ "$(readlink -f "$(findmnt -T /sysroot -no SOURCE)")" = "$(readlink -f "$ROOT_MAPPER")" ]
}

luks_cmdline_present() {
    grep -Eq '(^| )rd\.luks\.name=[^ ]+=root( |$)' /proc/cmdline
}

composefs_cmdline_present() {
    grep -Eq '(^| )composefs=[0-9a-f]{128}( |$)' /proc/cmdline
}

secure_boot_disabled() {
    mokutil --sb-state 2>/dev/null | grep -qi 'disabled'
}

nvidia_target_present() {
    lspci -n | grep -qi '10de:2544'
}

enough_free_space() {
    local available_bytes
    local required_bytes

    [[ "$MIN_FREE_GIB" =~ ^[0-9]+$ ]] || return 1
    available_bytes="$(df --output=avail -B1 /sysroot | tail -1 | tr -d ' ')"
    required_bytes=$((MIN_FREE_GIB * 1024 * 1024 * 1024))
    [ "$available_bytes" -ge "$required_bytes" ]
}

check "running as root" test "$(id -u)" -eq 0
check "booted through UEFI" test -d /sys/firmware/efi
check "systemd-boot is the current boot loader" sh -c \
    "bootctl status 2>/dev/null | grep -q 'Product: systemd-boot'"
check "Secure Boot is disabled for the unsigned Arch boot payload" secure_boot_disabled
check "composefs deployment is active" composefs_cmdline_present
check "LUKS root kernel argument is present" luks_cmdline_present
check "${ROOT_MAPPER} exists" test -b "$ROOT_MAPPER"
check "/sysroot uses ${ROOT_MAPPER}" root_uses_expected_mapper
check "unlocked root filesystem is Btrfs" root_is_btrfs
check "LUKS mapping root is active" cryptsetup status root
check "at least ${MIN_FREE_GIB} GiB is free" enough_free_space
check "persistent home exists for ${TARGET_USER}" test -d "/var/home/${TARGET_USER}"
check "target RTX 3060 is present" nvidia_target_present
check "bootc is installed" test -x /usr/bin/bootc
check "no SELinux policy is enforcing" sh -c \
    'command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" = Disabled ]'

echo
echo "Disk/filesystem labels (read-only):"
lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS

echo
echo "Current bootc state (read-only):"
bootc status

echo
if [ "$fail" -ne 0 ]; then
    echo "Preflight failed. Do not stage or reboot into the Arch image."
    exit 1
fi

echo "Preflight passed. No partitions, labels, encryption metadata, or boot entries were changed."
