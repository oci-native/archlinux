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

ARG_USERNAME=""
ARG_PASSWORD=""
IMAGE_REFS=()

if [ "$#" -gt 0 ]; then
    if [ "$#" -ne 3 ]; then
        echo "Usage: $0 [image-ref] [username] [password]"
        exit 1
    fi
    IMAGE_REFS=("$1")
    ARG_USERNAME="$2"
    ARG_PASSWORD="$3"
else
    IMAGE_REFS_STR="${BOOTC_IMAGE_REFS:-${BOOTC_LAPTOP_IMAGE_REF:-}}"
    if [ -z "$IMAGE_REFS_STR" ]; then
        echo "Usage: $0 [image-ref] [username] [password]"
        echo "Alternatively set BOOTC_IMAGE_REFS in ${ENV_FILE}"
        exit 1
    fi
    read -r -a IMAGE_REFS <<< "$IMAGE_REFS_STR"
fi

OUTPUT_DIR="$REPO_DIR"
IMG="$OUTPUT_DIR/bootable-laptop.img"
DISK_SIZE="${BOOTC_DISK_SIZE:-64G}"
SOURCE_IMAGE_REF="${BOOTC_SOURCE_IMAGE_REF:-${IMAGE_REFS[0]}}"

sudo -v

if registry_has_credentials "$SOURCE_IMAGE_REF" "$ARG_USERNAME" "$ARG_PASSWORD"; then
    registry_auth podman-login "$SOURCE_IMAGE_REF" "$ARG_USERNAME" "$ARG_PASSWORD"
fi

echo "## Creating ${DISK_SIZE} disk image"
if [ ! -e "$IMG" ]; then
    fallocate -l "$DISK_SIZE" "$IMG"
fi

echo ""
echo "## Running bootc install to-disk"
sudo podman run \
    --rm --privileged --pid=host --ipc=host --network=host \
    --security-opt label=type:unconfined_t \
    -v /var/lib/containers:/var/lib/containers \
    -v /etc/containers:/etc/containers \
    -v /dev:/dev \
    -v "$OUTPUT_DIR:/data" \
    "$SOURCE_IMAGE_REF:latest" \
    bootc install to-disk \
    --composefs-backend \
    --via-loopback /data/bootable-laptop.img \
    --filesystem ext4 \
    --wipe \
    --bootloader systemd

echo ""
echo "## Disk image created: $IMG"
ls -lh "$IMG"
