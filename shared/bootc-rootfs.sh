#!/usr/bin/env bash
set -euo pipefail

# Standard bootc root layout, directly following bootcrew/mono. Persistent
# writable paths resolve into /var while the deployed /usr stays composefs
# backed and read-only.
rm -rf \
    /boot \
    /home \
    /root \
    /tmp \
    /usr/local \
    /srv \
    /opt \
    /mnt \
    /var \
    /usr/lib/sysimage/log \
    /usr/lib/sysimage/cache/pacman/pkg

find /run -mindepth 1 -maxdepth 1 ! -name .containerenv \
    -exec rm -rf -- {} +

install -d /sysroot /boot /run /usr/lib/ostree /var
install -d -m 1777 /tmp

ln -sT sysroot/ostree /ostree
ln -sT var/roothome /root
ln -sT var/srv /srv
ln -sT var/opt /opt
ln -sT var/mnt /mnt
ln -sT var/home /home
ln -sT ../var/usrlocal /usr/local

printf '%s\n' \
    'd /var/opt 0755 root root -' \
    'd /var/home 0755 root root -' \
    'd /var/srv 0755 root root -' \
    'd /var/mnt 0755 root root -' \
    'd /var/usrlocal 0755 root root -' \
    'd /var/roothome 0700 root root -' \
    'd /run/media 0755 root root -' \
    > /usr/lib/tmpfiles.d/bootc-base-dirs.conf

printf '%s\n' \
    '[composefs]' \
    'enabled = yes' \
    '[sysroot]' \
    'readonly = true' \
    > /usr/lib/ostree/prepare-root.conf
