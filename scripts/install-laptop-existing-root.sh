#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${REPO_DIR}/.env"

# shellcheck source=scripts/registry-auth.sh
source "${SCRIPT_DIR}/registry-auth.sh"

if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

DEFAULT_IMAGE_REFS="${BOOTC_IMAGE_REFS:-}"
IMAGE_REF="${1:-${BOOTC_LAPTOP_IMAGE_REF:-${DEFAULT_IMAGE_REFS%% *}}}"
ARG_USERNAME="${2:-}"
ARG_PASSWORD="${3:-}"
ROOT_PART="${BOOTC_ROOT_PART:-/dev/nvme0n1p7}"
ESP_PART="${BOOTC_ESP_PART:-/dev/nvme0n1p6}"
TARGET_ROOT="${BOOTC_TARGET_ROOT:-/}"
MIN_FREE_GIB="${BOOTC_MIN_FREE_GIB:-30}"

resolve_image_ref() {
    local image="$1"
    local final_component="${image##*/}"

    if [[ "$image" == *@* || "$final_component" == *:* ]]; then
        printf '%s\n' "$image"
    else
        printf '%s:latest\n' "$image"
    fi
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "run as root: sudo $0 [image-ref] [username] [password]"
}

confirm_laptop() {
    local product=""
    local board=""

    product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
    board="$(cat /sys/class/dmi/id/board_name 2>/dev/null || true)"

    echo "## Product: ${product:-unknown}"
    echo "## Board: ${board:-unknown}"

    [[ "$product" == *X1404ZA* || "$board" == *X1404ZA* ]] || \
        die "this does not look like the ASUS Vivobook X1404ZA target"
}

confirm_partitions() {
    [ -b "$ROOT_PART" ] || die "root partition not found: $ROOT_PART"
    [ -b "$ESP_PART" ] || die "ESP partition not found: $ESP_PART"

    local root_fstype=""
    local esp_fstype=""
    root_fstype="$(blkid -o value -s TYPE "$ROOT_PART" 2>/dev/null || true)"
    esp_fstype="$(blkid -o value -s TYPE "$ESP_PART" 2>/dev/null || true)"

    [ "$root_fstype" = "ext4" ] || die "$ROOT_PART must be ext4, found ${root_fstype:-unknown}"
    [ "$esp_fstype" = "vfat" ] || die "$ESP_PART must be vfat, found ${esp_fstype:-unknown}"

    echo "## Partition layout:"
    lsblk -f /dev/nvme0n1

    for part in /dev/nvme0n1p1 /dev/nvme0n1p2 /dev/nvme0n1p3 /dev/nvme0n1p4 /dev/nvme0n1p5; do
        [ -e "$part" ] || die "expected Windows/OEM partition missing: $part"
    done
}

confirm_free_space() {
    local available_bytes
    local required_bytes

    [[ "$MIN_FREE_GIB" =~ ^[0-9]+$ ]] || die "BOOTC_MIN_FREE_GIB must be an integer"
    available_bytes="$(df --output=avail -B1 "$TARGET_ROOT" | tail -1 | tr -d ' ')"
    required_bytes=$((MIN_FREE_GIB * 1024 * 1024 * 1024))

    [ "$available_bytes" -ge "$required_bytes" ] || \
        die "$TARGET_ROOT needs at least ${MIN_FREE_GIB} GiB free for the root-owned image pull"

    echo "## Free space: $((available_bytes / 1024 / 1024 / 1024)) GiB"
}

backup_esp() {
    local backup_dir="/var/home/${BOOTC_USER:-bupdlap}/bootc-install-backups"
    local stamp
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"

    mkdir -p "$backup_dir"
    tar -C /boot -czf "$backup_dir/esp-${stamp}.tar.gz" .
    echo "## ESP backup: $backup_dir/esp-${stamp}.tar.gz"
}

main() {
    local resolved_image

    require_root
    [ -n "$IMAGE_REF" ] || die "missing image ref"
    resolved_image="$(resolve_image_ref "$IMAGE_REF")"

    confirm_laptop
    confirm_partitions
    confirm_free_space
    echo "## Image: ${resolved_image}"

    if registry_has_credentials "$IMAGE_REF" "$ARG_USERNAME" "$ARG_PASSWORD"; then
        registry_auth podman-login "$IMAGE_REF" "$ARG_USERNAME" "$ARG_PASSWORD"
    fi

    echo ""
    echo "## This will convert the existing Arch root at ${ROOT_PART} to bootc."
    echo "## Windows/OEM partitions p1-p5 are expected to remain untouched."
    echo "## /boot and boot loader content will be reinitialized after an ESP backup."
    read -r -p "Type 'convert ${ROOT_PART}' to continue: " confirm
    [ "$confirm" = "convert ${ROOT_PART}" ] || die "aborted"

    backup_esp

    podman run \
        --rm --privileged --pid=host --ipc=host --network=host \
        --security-opt label=type:unconfined_t \
        -v /dev:/dev \
        -v /var/lib/containers:/var/lib/containers \
        -v "${TARGET_ROOT}:/target" \
        "$resolved_image" \
        bootc install to-existing-root \
        --bootloader systemd

    if [ -x /usr/bin/bootc-sync-esp ]; then
        echo ""
        echo "## bootc install completed. Syncing ESP from generated loader state."
        /usr/bin/bootc-sync-esp
    else
        echo ""
        echo "## bootc install completed. ESP sync will run on first boot from the image."
    fi

    echo ""
    echo "## Done. Reboot when ready."
    echo "## First boot will prompt on tty1 for the local bupdlap password before GDM starts."
}

main "$@"
