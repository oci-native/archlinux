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
PUSH_IMAGE=1

if [ "${1:-}" = "--local" ]; then
    PUSH_IMAGE=0
    IMAGE_REFS=("${BOOTC_LAPTOP_LOCAL_TAG:-localhost/archlinux-laptop}")
elif [ "$#" -gt 0 ]; then
    if [ "$#" -ne 3 ]; then
        echo "Usage: $0 [image-ref] [username] [password]"
        echo "Alternatively set BOOTC_IMAGE_REFS plus registry credentials in ${ENV_FILE}"
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

github_latest_release_tag() {
    local repo="$1"
    local -a curl_args=(-fsSL)
    local token="${GITHUB_TOKEN:-${GH_TOKEN:-${GHCR_TOKEN:-}}}"

    if [ -n "$token" ]; then
        curl_args+=(-H "Authorization: Bearer ${token}")
    fi

    curl "${curl_args[@]}" "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name'
}

BOOTC_VERSION="${BOOTC_VERSION:-$(github_latest_release_tag bootc-dev/bootc)}"

if [ -z "$BOOTC_VERSION" ] || [ "$BOOTC_VERSION" = "null" ]; then
    echo "ERROR: failed to resolve latest bootc release"
    exit 1
fi

default_podman_cmd() {
    if [ "$PUSH_IMAGE" -eq 0 ]; then
        local runroot="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/containers"
        printf 'podman --root %s --runroot %s\n' "$HOME/.local/share/containers/storage" "$runroot"
    else
        printf 'sudo podman\n'
    fi
}

read -r -a PODMAN <<< "${BOOTC_PODMAN_CMD:-$(default_podman_cmd)}"

if [ "${PODMAN[0]}" = "sudo" ]; then
    sudo -v
fi

if [ "$PUSH_IMAGE" -eq 1 ]; then
    for image_ref in "${IMAGE_REFS[@]}"; do
        registry_auth check "$image_ref" "$ARG_USERNAME" "$ARG_PASSWORD"
    done

    for image_ref in "${IMAGE_REFS[@]}"; do
        registry_auth podman-login "$image_ref" "$ARG_USERNAME" "$ARG_PASSWORD"
    done
fi

BASE_IMAGE_TAG="localhost/archlinux-bootc-base:latest"
FINAL_IMAGE_TAG="localhost/archlinux-laptop:latest"

echo "## Using bootc ${BOOTC_VERSION}"
echo "## Building base image"
"${PODMAN[@]}" build --pull=always --network=host \
    --build-arg "BOOTC_VERSION=${BOOTC_VERSION}" \
    -f "$REPO_DIR/Containerfile.base" \
    -t "$BASE_IMAGE_TAG" \
    "$REPO_DIR"

echo ""
echo "## Building laptop image"
"${PODMAN[@]}" build --network=host \
    --build-arg "BASE_IMAGE=${BASE_IMAGE_TAG}" \
    -f "$REPO_DIR/Containerfile.laptop" \
    -t "$FINAL_IMAGE_TAG" \
    "$REPO_DIR"

if [ "$PUSH_IMAGE" -eq 1 ]; then
    for image_ref in "${IMAGE_REFS[@]}"; do
        target_image_tag="${image_ref}:latest"
        echo ""
        echo "## Pushing to $target_image_tag"
        "${PODMAN[@]}" tag "$FINAL_IMAGE_TAG" "$target_image_tag"
        "${PODMAN[@]}" push "$target_image_tag"
    done

    echo ""
    echo "## Done. Laptop image pushed to:"
    for image_ref in "${IMAGE_REFS[@]}"; do
        echo "##   ${image_ref}:latest"
    done
else
    echo ""
    echo "## Local build complete: ${IMAGE_REFS[0]}:latest"
    "${PODMAN[@]}" tag "$FINAL_IMAGE_TAG" "${IMAGE_REFS[0]}:latest"
fi
