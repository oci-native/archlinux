#!/bin/bash
# shellcheck disable=SC2329
set -euo pipefail

ROOT_PART="${BOOTC_ROOT_PART:-/dev/nvme0n1p7}"
ESP_PART="${BOOTC_ESP_PART:-/dev/nvme0n1p6}"

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

product_matches() {
    local product board
    product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
    board="$(cat /sys/class/dmi/id/board_name 2>/dev/null || true)"
    [[ "$product" == *X1404ZA* || "$board" == *X1404ZA* ]]
}

partition_type_is() {
    local part="$1"
    local type="$2"
    [ "$(lsblk -no FSTYPE "$part" 2>/dev/null || true)" = "$type" ]
}

wifi_device_present() {
    lspci -nn | grep -q '14c3:7902'
}

mt7921_option_present() {
    grep -Rqs '^options mt7921e .*disable_aspm=1' /etc/modprobe.d
}

windows_partitions_present() {
    for part in /dev/nvme0n1p1 /dev/nvme0n1p2 /dev/nvme0n1p3 /dev/nvme0n1p4 /dev/nvme0n1p5; do
        [ -e "$part" ] || return 1
    done
}

check "ASUS Vivobook X1404ZA detected" product_matches
check "Windows/OEM partitions p1-p5 exist" windows_partitions_present
check "ESP ${ESP_PART} is vfat" partition_type_is "$ESP_PART" vfat
check "Arch root ${ROOT_PART} is ext4" partition_type_is "$ROOT_PART" ext4
check "MT7902 PCI device exists" wifi_device_present
check "current system has mt7921e disable_aspm workaround" mt7921_option_present
check "podman available" sh -c 'command -v podman >/dev/null 2>&1'
check "bootctl available" sh -c 'command -v bootctl >/dev/null 2>&1'
check "efibootmgr available" sh -c 'command -v efibootmgr >/dev/null 2>&1'

echo ""
lsblk -f /dev/nvme0n1

exit "$fail"
