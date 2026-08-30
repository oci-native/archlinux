#!/usr/bin/env bash
# Provision the machine-local Cloudflare Tunnel token for the opt-in
# cloudflared-tunnel.service shipped in the image.
#
# The token never enters the image or this repository: it is decrypted from a
# sops-encrypted env file (kept wherever the operator wants) and installed as
# root-only /etc/cloudflared/tunnel.env, which is the sole activation switch
# for the unit. /etc persists across bootc switches, so this survives upgrades.
#
# Usage: sudo scripts/setup-cloudflared-tunnel.sh <sops-encrypted-env-file>
# The encrypted file must decrypt to a line: TUNNEL_TOKEN=<token>
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0 <sops-encrypted-env-file>" >&2
    exit 1
fi

if [ $# -ne 1 ] || [ ! -f "$1" ]; then
    echo "Usage: sudo $0 <sops-encrypted-env-file>" >&2
    exit 1
fi

command -v sops >/dev/null || { echo "sops is not installed" >&2; exit 1; }

plaintext="$(sops -d "$1")"
grep -q '^TUNNEL_TOKEN=.' <<<"$plaintext" || {
    echo "Decrypted file does not contain a TUNNEL_TOKEN= line" >&2
    exit 1
}

install -d -m 0755 /etc/cloudflared
umask 077
printf '%s\n' "$plaintext" > /etc/cloudflared/tunnel.env
chmod 0600 /etc/cloudflared/tunnel.env

# `cloudflared service install` (e.g. from a Homebrew binary) writes a
# token-embedded /etc/systemd/system/cloudflared.service; retire it so two
# tunnels never race for the same connector.
if [ -f /etc/systemd/system/cloudflared.service ]; then
    systemctl disable --now cloudflared.service || true
    rm /etc/systemd/system/cloudflared.service
    echo "Removed legacy cloudflared.service from 'cloudflared service install'"
fi

systemctl daemon-reload
if [ -x /usr/bin/cloudflared ]; then
    systemctl enable --now cloudflared-tunnel.service
    systemctl --no-pager --lines 5 status cloudflared-tunnel.service || true
else
    systemctl enable cloudflared-tunnel.service
    echo "/usr/bin/cloudflared not present on this deployment yet;"
    echo "the tunnel will start on first boot of an image that ships it."
fi
