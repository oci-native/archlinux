#!/usr/bin/env bash
set -euo pipefail

# The two systemd paths are required by bootc's dracut module on Arch.
# The explicit storage modules make the non-hostonly image independently
# verifiable for this machine's LUKS2-on-Btrfs root.
install -d /usr/lib/dracut/dracut.conf.d
printf '%s\n' \
    'systemdsystemconfdir=/etc/systemd/system' \
    'systemdsystemunitdir=/usr/lib/systemd/system' \
    > /usr/lib/dracut/dracut.conf.d/30-archlinux-bootc-module.conf
printf '%s\n' \
    'reproducible=yes' \
    'hostonly=no' \
    'compress=zstd' \
    'add_dracutmodules+=" ostree bootc crypt dm btrfs tpm2-tss "' \
    > /usr/lib/dracut/dracut.conf.d/30-archlinux-bootc-container-build.conf

kernel_dir="$(
    find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d |
        sort -V |
        tail -1
)"
test -n "$kernel_dir"
dracut --force "${kernel_dir}/initramfs.img"
