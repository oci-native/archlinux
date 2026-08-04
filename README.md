# Arch Linux bootc PC image

An Arch Linux workstation image for bootc hosts. It provides GNOME, Hyprland,
current AMD/NVIDIA support, and a focused desktop/developer toolset.

The image is built from `Containerfile.base` and `Containerfile.pc`, then
rechunked with Chunkah into content-based OCI layers before it is published.
The default registry target is `ghcr.io/oci-native/archlinux:latest`.

## Quick start

Requirements: rootless Podman, [Task](https://taskfile.dev/), and sufficient
local storage for an Arch desktop image. Confirm rootless Podman first:

```sh
podman info --format 'rootless={{.Host.Security.Rootless}}'
```

Create local registry configuration. Do not commit this file:

```sh
cp .env.example .env
```

Build, rechunk, and validate the deployable image:

```sh
task build
```

To rebuild every Containerfile without using cached layers, rechunk, validate,
and publish the result, set `GHCR_USERNAME` and `GHCR_TOKEN` in `.env`, then
run `rebuild-push`. The token requires the GitHub `write:packages` scope:

```sh
task rebuild-push
```

## Tasks

| Task | Purpose |
| --- | --- |
| `task build-base` | Build only the base bootc image. |
| `task build-pc` | Build only the flat PC image using the existing base image. |
| `task build-flat` | Build the base image, then the flat PC image. |
| `task rechunk` | Split the flat image into up to 96 content-based layers. |
| `task validate` | Validate the bootc, composefs, and initramfs boot path. |
| `task build` | Build, rechunk, and validate. |
| `task rebuild` | Rebuild both Containerfiles without cache, rechunk, and validate. |
| `task push` | Build, rechunk, validate, and push to GHCR as `:latest`. |
| `task rebuild-push` | Rebuild from the ground up without cache, rechunk, validate, and push. |
| `sudo task disk` | Create a bootable UEFI disk image. |
| `sudo task switch-preflight` | Read-only safety checks for the current Bluefin host. |
| `sudo task switch` | Confirm and stage the Arch deployment; it never reboots. |

Choose the narrowest task for the change being tested. `build-base` stops after
the shared base image, while `build-pc` rebuilds only the workstation layer and
requires the local base image to exist. `build-flat` runs both stages in order.

The two complete publishing paths are:

```text
task push:
  base (cached) -> PC (cached) -> rechunk -> validate -> push

task rebuild-push:
  base (--no-cache) -> PC (--no-cache) -> rechunk -> validate -> push
```

`rebuild-push` does not delete Podman images or globally clear the build cache;
it bypasses the cache for this build only.

Override the target repository when needed:

```sh
task push IMAGE_REPOSITORY=ghcr.io/example/archlinux
```

The local outputs are:

- `localhost/archlinux-pc:flat` — the direct Containerfile result.
- `localhost/archlinux-pc:latest` — the validated, rechunked deployment image.

## Image delivery

Chunkah reads the Arch pacman database and produces stable, content-based OCI
layers. The 96-layer value is a cap, not an exact target; the tool may emit
fewer layers when it can pack components more efficiently.

The final push uses OCI `zstd:chunked`. Chunkah keeps unchanged content in
reusable layers; zstd:chunked lets compatible clients fetch changed ranges
within changed layers. Override the cap with `CHUNKAH_MAX_LAYERS=...`.

The project intentionally uses Chunkah rather than an RPM-only rechunker,
because Chunkah supports pacman/ALPM images.

## What is included

- GNOME/GDM and Hyprland desktop sessions
- Chromium, Firefox, terminals, editors, Git, and common development tools
- NetworkManager, systemd-resolved, PipeWire, Bluetooth, and power profiles
- AMD microcode, `nvidia-open`, and Realtek firmware
- LUKS, Btrfs, dracut, systemd-boot, OSTree, and bootc support

Packages come from official Arch repositories except documented AUR desktop
exceptions. The image contains no dotfiles, credentials, Flatpak remotes, or
curl/npm-installed applications.

See [the architecture document](docs/laptop-bootc-architecture.md) for the
full image policy and design.

## Switching an existing Bluefin host

This workflow is only for a host that is already a composefs/UKI bootc system
with a LUKS-on-Btrfs root. It stages a new deployment; it does not repartition,
format, recreate LUKS, or reboot.

Run the read-only preflight:

```sh
sudo task switch-preflight
```

Then explicitly confirm the staged switch:

```sh
sudo task switch
```

Before rebooting, verify `bootc status` shows Arch as staged and Bluefin as the
rollback deployment. Keep Secure Boot disabled until a signed Arch UKI path is
available.

## TPM unlock and VM testing

TPM enrollment is host state, not image build state. After booting an image
with TPM initramfs support, enroll a token while retaining a passphrase slot:

```sh
sudo systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrs=7+14 \
  /dev/nvme0n1p2
```

For separate UEFI/QEMU testing, create a disk image:

```sh
sudo task disk
```

This does not replace testing the real host’s LUKS kernel arguments and GPU
path before staging a switch.
