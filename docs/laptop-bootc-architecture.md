# Arch Linux Laptop bootc Architecture

```mermaid
flowchart TD
    subgraph Inputs["Inputs"]
        A["archlinux/archlinux:latest"]
        B["arch-bootc-hetzner patterns"]
        C["public dotfiles repo"]
        D["ASUS Vivobook X1404ZA host facts"]
    end

    subgraph Base["Containerfile.base"]
        B1["Move pacman state to /usr/lib/sysimage"]
        B2["Install base boot stack\nlinux, dracut, ostree, podman, skopeo"]
        B3["Build bootc v1.16.4 from source"]
        B4["Set composefs + readonly sysroot"]
        B5["Keep /opt image-managed\nrequired by Arch desktop/AUR packages"]
    end

    subgraph Laptop["Containerfile.laptop"]
        L1["Install GNOME + GDM + i3"]
        L2["Install NetworkManager + iwd + firmware"]
        L3["Install dev/container tools\nDocker, kubectl, helm, k9s, k3d, kind"]
        L4["Install AUR packages\nChrome, Brave, DisplayLink, EVDI, etc."]
        L5["Clone and stow dotfiles"]
        L6["Enable laptop services"]
    end

    subgraph Hardware["Laptop Hardware Support"]
        H1["MT7902 Wi-Fi uses in-kernel mt7921e"]
        H2["/etc/modprobe.d/mt7902.conf\noptions mt7921e disable_aspm=1"]
        H3["NetworkManager Wi-Fi powersave disabled"]
        H4["GDM forced to X11\nWaylandEnable=false"]
    end

    subgraph Boot["Boot/install model"]
        I1["ghcr.io/oci-native/archlinux-laptop:latest"]
        I2["bootc install to-existing-root\n/dev/nvme0n1p7"]
        I3["ESP mounted at /boot\n/dev/nvme0n1p6"]
        I4["bootc-sync-esp service copies\nsystemd-boot, loader entries,\nkernel, initramfs, ucode"]
        I5["Next reboot uses bootc-managed Arch"]
    end

    subgraph Validation["Current validation"]
        V1["Preflight passed\nVivobook + partition layout + MT7902"]
        V2["Shell scripts pass shellcheck + bash -n"]
        V3["Image built successfully\n022daae026ba"]
        V4["Image probe passed\nbootc, kernel, k3d, kind, services"]
        V5["Public-image audit passed\nno credentials, histories,\nprivate keys, or user caches"]
    end

    subgraph Risks["Known review points"]
        R1["bootc lint warns non-empty /boot\nArch linux package writes kernel files there"]
        R2["ndiswrapper-dkms build warning\nnot primary Wi-Fi path"]
        R3["Image is large: about 23.5 GB local size"]
        R4["Live conversion is intentionally not run yet"]
    end

    A --> B1
    B --> B1
    B1 --> B2 --> B3 --> B4 --> B5 --> L1
    C --> L5
    D --> H1
    L1 --> L2 --> L3 --> L4 --> L5 --> L6 --> I1
    H1 --> H2 --> L2
    H3 --> L2
    H4 --> L1
    I1 --> I2 --> I3 --> I4 --> I5
    L6 --> V4
    I1 --> V3
    D --> V1
    V1 --> Risks
    V2 --> Risks
    V3 --> Risks
    V4 --> Risks
    V5 --> Risks
```

## Decision Notes

- The image keeps `/opt` as image-managed because Arch desktop/AUR packages install package-owned payloads there, especially browser, DisplayLink, and Intel/PyTorch dependencies.
- The primary Wi-Fi support is the stock kernel `mt7921e` driver with `disable_aspm=1`; experimental DKMS/ndiswrapper artifacts are documented only as fallback notes.
- The install path is scripted but intentionally guarded. It validates the ASUS model, partition layout, and explicit confirmation before `bootc install to-existing-root`.
- The ESP sync service exists because the Arch `linux` package writes kernel artifacts into `/boot`, which differs from stricter bootc base-image expectations.
- The public-image audit preserves installed AUR packages while excluding package build caches, shell histories, SSH material, personal Git identity, private keys, and credential-like content.
