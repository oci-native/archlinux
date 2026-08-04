# Arch Linux bootc laptop image

This repository builds a rolling Arch Linux workstation image for the current
Bluefin bootc host. It includes GNOME, Hyprland, Chromium, Firefox, and
terminal/development utilities from the official Arch repositories. It keeps
AUR use limited to explicit desktop exceptions and does not include downloaded
application installers, Flatpak remotes, or user dotfiles.

The base layout follows
[`bootcrew/mono`](https://github.com/bootcrew/mono/tree/main/arch): a separate
upstream bootc builder stage, pacman state under `/usr/lib/sysimage`, a generic
dracut image, bootc's standard persistent-root layout, and composefs enabled in
`/usr/lib/ostree/prepare-root.conf`. The desktop layer adds the workstation
package set declared in `Containerfile.laptop`.

The image tracks the current official Arch repositories on every build:

- `archlinux/archlinux:latest`
- a full `pacman -Syu`
- the latest upstream bootc release resolved by the build script

Bootc is the only source-built component because Arch does not currently
publish a bootc package. Its Git/Rust/build dependencies are removed in the
same image layer.

## Included desktop

The graphical system is workstation-oriented:

- GDM and the full GNOME desktop group
- Hyprland, Hyprlock, Waybar, Rofi, Dunst, Wlogout, and their desktop portal
- GNOME Console, Ghostty, Files, and Settings
- Chromium and Firefox
- NetworkManager with systemd-resolved DNS
- PipeWire and WirePlumber
- power-profiles-daemon
- brightness, audio, Bluetooth UI, GPU monitor, wallpaper, icon theme, and Nerd
  Font tools
- Matugen for opt-in dynamic color generation
- fastfetch, Git, Neovim, Vim, Stow, Zsh, and sudo

`wlogout` is installed from AUR through `yay` as an explicit Hyprland desktop
exception because it is not available from the enabled official Arch
repositories checked for this image. The final image keeps `yay` installed for
that exception. `awww` is included from the official repositories for Wayland
wallpaper handling. `swww` is still not included; add it only if the image
policy allows another AUR exception or an official package becomes available.

The hardware/boot set is limited to what the current machine needs:

- AMD microcode
- the official `nvidia-open` driver for the RTX 3060
- Realtek firmware for the onboard network controller
- Linux, dracut, systemd-boot, bootc, OSTree, and skopeo
- cryptsetup and Btrfs support in the initramfs
- EFI/systemd-boot tools

Except for the explicit AUR exceptions documented above, these packages come
from the official Arch repositories.

## Build

For a local build on the current bootc host, use rootful Podman because its
immutable `/usr` does not currently provide working `newuidmap`/`newgidmap`
privileges for rootless Podman:

```sh
sudo ./scripts/build-laptop.sh --local
```

The resulting tag is `localhost/archlinux-laptop:latest` in root's Podman
storage. Inspect it with `sudo podman images`.

Post-build validation is intentionally limited to the bootc/composefs boot
path and the encrypted Btrfs initramfs required by this host. It does not
enforce workstation package policy.

The temporary handoff registry is `ttl.sh`, which needs no account or
credentials:

```sh
sudo ./scripts/build-laptop.sh
```

`ttl.sh` is ephemeral: an unqualified TTL such as `:latest` expires after one
hour. The host tracks `ttl.sh/oci-native/archlinux:latest`; move the image to a
durable registry before configuring long-term upgrades.

## Encrypted Bluefin switch

Do not repartition or run `bootc install to-existing-root` on the current
machine. It already has the correct bootc disk foundation:

- UEFI and systemd-boot
- composefs/UKI deployment
- an unlocked LUKS mapping at `/dev/mapper/root`
- a Btrfs physical root
- persistent state and home under `/var`

An in-place `bootc switch` changes only the staged OS deployment. It does not
format the NVMe, recreate LUKS, or change partition/filesystem labels. The
current Bluefin deployment remains the rollback entry.

Run the read-only preflight first:

```sh
sudo ./scripts/validate-bluefin-switch.sh
```

After building and pushing, stage the requested tag:

```sh
sudo ./scripts/stage-bluefin-to-arch.sh \
  ttl.sh/oci-native/archlinux:latest
```

The staging script deliberately does not use `--apply` and does not reboot. It
saves recovery metadata under `/var/home/bupd/arch-switch-backups`, then shows
the staged and rollback deployments. It passes
`ttl.sh/oci-native/archlinux:latest` directly to `bootc switch`. It contains no
custom ESP, boot-entry, or bootloader handling; bootc remains solely
responsible for those operations.

Before the first reboot:

1. Confirm `bootc status` lists Arch as staged and Bluefin as rollback.
2. Keep Secure Boot disabled unless the Arch kernel and bootloader are signed
   with an enrolled key.
3. Ensure the systemd-boot menu is visible so Bluefin can be selected if Arch
   does not reach the LUKS prompt, a TTY, or GDM.

The persistent user is `bupd` (UID/GID 1000), matching `/var/home/bupd`.
Bootc preserves the deployed `/etc` account/password state during the switch;
the public image itself contains no password hash and installs no custom
first-boot or boot-loader helper service.

## TPM unlock for encrypted root

Bluefin's `ujust setup-luks-tpm-unlock` ultimately uses
`systemd-cryptenroll` with PCR `7+14`. This image keeps the same TPM2 unlock
policy without adding a custom wrapper: the initramfs includes dracut's
`tpm2-tss` module and the TPM2 userspace required by it.

The LUKS header itself is host state, so enrolling the TPM token is a one-time
live-system operation, not an image build step. After booting an image that
contains the TPM initramfs support, run:

```sh
sudo systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrs=7+14 \
  /dev/nvme0n1p2
```

Keep at least one passphrase slot enrolled. The passphrase remains the fallback
if TPM unlock is unavailable after firmware, Secure Boot policy, MOK, or TPM
changes. Verify enrollment with:

```sh
sudo cryptsetup luksDump /dev/nvme0n1p2 | sed -n '/Tokens:/,/Digests:/p'
```

To remove TPM auto-unlock:

```sh
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p2
```

## VM disk image

`./scripts/generate-laptop-disk.sh` creates `bootable-laptop.img` for separate
UEFI/QEMU testing. It is not a substitute for verifying the host-specific LUKS
kernel arguments and NVIDIA path before switching the real machine.
