# MT7902 fallback notes

This laptop reports a MediaTek MT7902 PCI device:

```text
14c3:7902 MediaTek MT7902 / Filogic 310
```

The current working boot path uses the in-kernel `mt7921e` module with:

```text
options mt7921e disable_aspm=1
```

The previous mutable system also had experimental DKMS/ndiswrapper artifacts:

- `mt7902-wifi/1.0.0`
- `mt7902-bt/1.0.0`
- `ndiswrapper/1.63`
- source checkout at `/home/bupdlap/gits/mt7902-dkms`

Do not make the bootc image depend on that experimental DKMS path by default.
If stock `mt7921e` stops binding after a kernel update, recover with wired USB
tethering, boot a previous bootc deployment, or package a pinned DKMS fallback
after validating it against the target Arch kernel.
