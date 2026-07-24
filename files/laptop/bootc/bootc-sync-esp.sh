#!/bin/bash
set -euo pipefail
shopt -s nullglob

BOOT="/boot"

log() { echo "bootc-sync-esp: $*"; }

find_esp() {
    if mountpoint -q /boot/efi; then
        printf '%s\n' /boot/efi
        return 0
    fi

    if mountpoint -q /boot; then
        if [ -d /boot/EFI ] || [ -d /boot/loader ] || findmnt -no FSTYPE /boot | grep -q '^vfat$'; then
            printf '%s\n' /boot
            return 0
        fi
    fi

    mkdir -p /boot/efi
    local efi_part=""
    efi_part=$(blkid -t PARTLABEL="EFI System" -o device 2>/dev/null | head -1 || true)
    if [ -z "$efi_part" ]; then
        efi_part=$(blkid -t TYPE="vfat" -o device 2>/dev/null | head -1 || true)
    fi
    if [ -z "$efi_part" ]; then
        log "no EFI partition found"
        return 1
    fi
    mount "$efi_part" /boot/efi
    printf '%s\n' /boot/efi
}

find_loader_dir() {
    local loader_dir=""

    if [ -L "$BOOT/loader" ]; then
        loader_dir=$(readlink -f "$BOOT/loader")
    fi

    if [ -z "$loader_dir" ] || [ ! -d "$loader_dir/entries" ]; then
        for candidate in "$BOOT"/loader.1 "$BOOT"/loader.0 "$BOOT"/loader; do
            if [ -d "$candidate/entries" ]; then
                loader_dir="$candidate"
                break
            fi
        done
    fi

    if [ -z "$loader_dir" ] || [ ! -d "$loader_dir/entries" ]; then
        log "no loader entries found under $BOOT"
        return 1
    fi

    printf '%s\n' "$loader_dir"
}

sync_efi_binaries() {
    local esp="$1"

    [ -f /usr/lib/systemd/boot/efi/systemd-bootx64.efi ] || return 0
    mkdir -p "$esp/EFI/BOOT" "$esp/EFI/systemd"
    cp /usr/lib/systemd/boot/efi/systemd-bootx64.efi "$esp/EFI/BOOT/BOOTX64.EFI"
    cp /usr/lib/systemd/boot/efi/systemd-bootx64.efi "$esp/EFI/systemd/systemd-bootx64.efi"
}

sync_loader_tree() {
    local esp="$1"
    local loader_dir="$2"
    local entries=("$loader_dir"/entries/*.conf)
    local default_entry=""
    local existing_loader_conf=""
    local entry

    if [ ${#entries[@]} -eq 0 ]; then
        log "no boot entries found in $loader_dir/entries"
        return 1
    fi

    if [ -f "$esp/loader/loader.conf" ]; then
        existing_loader_conf=$(mktemp)
        cp "$esp/loader/loader.conf" "$existing_loader_conf"
    fi

    mkdir -p "$esp/loader/entries"
    rm -f "$esp/loader/entries/"*.conf "$esp/loader/loader.conf"
    cp "${entries[@]}" "$esp/loader/entries/"

    for entry in "$esp"/loader/entries/*.conf; do
        sed -i 's|/boot/ostree/|/ostree/|g' "$entry"
    done

    if [ -n "$existing_loader_conf" ] && [ -f "$existing_loader_conf" ]; then
        default_entry=$(awk '/^default / {print $2; exit}' "$existing_loader_conf")
    fi
    if [ -z "$default_entry" ] || [ ! -f "$esp/loader/entries/$default_entry" ]; then
        if [ -f "$esp/loader/entries/ostree-2.conf" ]; then
            default_entry="ostree-2.conf"
        else
            default_entry=$(basename "${entries[0]}")
        fi
    fi

    printf 'default %s\ntimeout 5\n' "$default_entry" > "$esp/loader/loader.conf"
    [ -z "$existing_loader_conf" ] || rm -f "$existing_loader_conf"
}

configure_loader_in_place() {
    local loader_dir="$1"
    local entries=("$loader_dir"/entries/*.conf)
    local default_entry=""
    local entry

    if [ ${#entries[@]} -eq 0 ]; then
        log "no boot entries found in $loader_dir/entries"
        return 1
    fi

    for entry in "${entries[@]}"; do
        sed -i 's|/boot/ostree/|/ostree/|g' "$entry"
    done

    if [ -f "$loader_dir/loader.conf" ]; then
        default_entry=$(awk '/^default / {print $2; exit}' "$loader_dir/loader.conf")
    fi
    if [ -z "$default_entry" ] || [ ! -f "$loader_dir/entries/$default_entry" ]; then
        if [ -f "$loader_dir/entries/ostree-2.conf" ]; then
            default_entry="ostree-2.conf"
        else
            default_entry=$(basename "${entries[0]}")
        fi
    fi

    printf 'default %s\ntimeout 5\n' "$default_entry" > "$loader_dir/loader.conf"
}

sync_ostree_payloads() {
    local esp="$1"
    local ostree_dir
    local dest
    local kernels
    local initramfs

    rm -rf "$esp/ostree"
    for ostree_dir in "$BOOT"/ostree/default-*; do
        [ -d "$ostree_dir" ] || continue
        dest="$esp/ostree/$(basename "$ostree_dir")"
        mkdir -p "$dest"

        kernels=("$ostree_dir"/vmlinuz-*)
        [ ${#kernels[@]} -eq 0 ] || cp "${kernels[@]}" "$dest/"

        initramfs=("$ostree_dir"/initramfs-*)
        [ ${#initramfs[@]} -eq 0 ] || cp "${initramfs[@]}" "$dest/"
    done
}

esp=$(find_esp)
loader_dir=$(find_loader_dir)
log "ESP: $esp"
log "active loader: $loader_dir"

sync_efi_binaries "$esp"

if [ "$(readlink -f "$esp")" = "$(readlink -f "$BOOT")" ]; then
    configure_loader_in_place "$loader_dir"
    log "ESP is mounted at $BOOT; bootc payloads are already in place"
    log "ESP synced"
    exit 0
fi

sync_loader_tree "$esp" "$loader_dir"
sync_ostree_payloads "$esp"

log "ESP synced"
