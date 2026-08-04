#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 IMAGE_REPOSITORY [PODMAN_COMMAND ...]" >&2
  exit 2
fi

image_ref="$1"
shift

if [ "$#" -eq 0 ]; then
  set -- podman
fi
container_cli=("$@")

first_part="${image_ref%%/*}"
if [ "$first_part" = "$image_ref" ]; then
  host=docker.io
elif [[ "$first_part" == *.* || "$first_part" == *:* || "$first_part" = localhost ]]; then
  host="$first_part"
else
  host=docker.io
fi

if [ "$host" = ttl.sh ]; then
  exit 0
fi

if "${container_cli[@]}" login --get-login "$host" >/dev/null 2>&1; then
  echo "Using existing Podman credentials for ${host}."
  exit 0
fi

case "$host" in
  ghcr.io)
    username="${GHCR_USERNAME:-}"
    password="${GHCR_TOKEN:-}"
    hint='Log in with `podman login ghcr.io`, or set GHCR_USERNAME and GHCR_TOKEN.'
    ;;
  docker.io | index.docker.io | registry-1.docker.io)
    username="${DOCKERHUB_USERNAME:-}"
    password="${DOCKERHUB_TOKEN:-}"
    hint='Log in with `podman login docker.io`, or set DOCKERHUB_USERNAME and DOCKERHUB_TOKEN.'
    ;;
  *)
    username="${BOOTC_USERNAME:-}"
    password="${BOOTC_PASSWORD:-}"
    hint="Log in with \`podman login ${host}\`, or set BOOTC_USERNAME and BOOTC_PASSWORD."
    ;;
esac

if [ -z "$username" ] || [ -z "$password" ]; then
  echo "ERROR: missing credentials for ${image_ref} (${host}). ${hint}" >&2
  exit 1
fi

printf '%s\n' "$password" | "${container_cli[@]}" login "$host" --username "$username" --password-stdin
