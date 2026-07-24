#!/bin/bash
set -euo pipefail

readonly USERNAME="${BOOTC_FIRSTBOOT_USER:-bupdlap}"
readonly STATE_DIR="/var/lib/archlinux-laptop"
readonly STATE_FILE="${STATE_DIR}/user-password-initialized"

if ! id "$USERNAME" >/dev/null 2>&1; then
    echo "ERROR: first-boot user does not exist: $USERNAME" >&2
    exit 1
fi

password_status="$(passwd -S "$USERNAME" | awk '{print $2}')"
if [ "$password_status" != "L" ]; then
    install -d -m 0700 "$STATE_DIR"
    touch "$STATE_FILE"
    exit 0
fi

clear
echo "Arch Linux laptop first-boot setup"
echo
echo "Set the local password for ${USERNAME}."
echo "The password is written only to this laptop and is not part of the image."
echo

until passwd "$USERNAME"; do
    echo
    echo "Password setup failed. Try again."
done

install -d -m 0700 "$STATE_DIR"
touch "$STATE_FILE"
echo
echo "Password configured. Starting the graphical login."
