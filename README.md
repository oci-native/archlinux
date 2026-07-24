# Arch Linux bootc laptop image

This repository defines a bootc-based Arch Linux image for the ASUS Vivobook
X1404ZA currently running this checkout.

The laptop variant is separate from `arch-bootc-hetzner` because the service
profile is different:

- Laptop: GNOME/GDM, i3 alternate session, NetworkManager/iwd, Bluetooth, TLP,
  DisplayLink/EVDI, Docker, PipeWire, desktop apps, MT7902 Wi-Fi workaround.
- Hetzner: networkd, cloud firewall defaults, serial console, qemu guest agent,
  k3s, and server boot assumptions.

## Build

```sh
cp .env.example .env
# Edit GHCR_USERNAME/GHCR_TOKEN if pushing to GHCR.
./scripts/build-laptop.sh
```

The first `BOOTC_IMAGE_REFS` entry is pushed as `:latest`.
The host running the build needs `podman`, `sudo`, `curl`, and `jq`.

For local validation without a registry push:

```sh
./scripts/build-laptop.sh --local
```

Local mode uses rootless podman storage under `~/.local/share/containers` so it
does not depend on the rootful `/var/lib/containers` store.

The image keeps `/opt` image-managed rather than symlinked to `/var/opt`
because several Arch desktop/AUR packages install package-owned payloads there.

## VM disk image

```sh
./scripts/generate-laptop-disk.sh
```

This creates `bootable-laptop.img` for UEFI/QEMU validation.

## Local laptop conversion

Run the preflight first:

```sh
./scripts/validate-laptop-preflight.sh
```

The install script is intentionally narrow. It expects this partition layout:

- Windows/OEM: `/dev/nvme0n1p1` through `/dev/nvme0n1p5`
- Linux ESP: `/dev/nvme0n1p6`
- Linux root: `/dev/nvme0n1p7`

Then convert the existing Arch root:

```sh
sudo ./scripts/install-laptop-existing-root.sh \
  ghcr.io/oci-native/archlinux-laptop@sha256:dcca61f60d27630fd7730dc08d5c68f55d66682b9fd66fde0aff686f051a00e1
```

The script backs up `/boot`, runs `bootc install to-existing-root`, and syncs
the systemd-boot loader payload to the ESP. It requires at least 30 GiB free
for the root-owned container image pull.

The public image contains no password hash. On the first boot, tty1 prompts for
a new local password for `bupdlap`; GDM starts only after password setup
succeeds. If bootc preserved an already-unlocked local password, this step is
marked complete automatically.

## Wi-Fi

The current laptop has a MediaTek MT7902 device (`14c3:7902`) bound to the
in-kernel `mt7921e` driver. The image bakes the current working workaround:

```text
options mt7921e disable_aspm=1
```

Experimental DKMS/ndiswrapper fallback notes are included in the image under
`/usr/share/archlinux-laptop/mt7902-fallback.md`, but the default boot path does
not depend on them.
