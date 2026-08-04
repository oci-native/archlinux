#!/usr/bin/env bash
set -euo pipefail

config="${XDG_CONFIG_HOME:-${HOME}/.config}/hypr/hyprland.lua"
exec /usr/bin/start-hyprland -- --config "${config}"
