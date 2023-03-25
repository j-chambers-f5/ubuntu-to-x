#!/bin/bash

set -x

# Install prereqs - Ubuntu
apt-get update && apt-get -y install \
  qemu-utils

# Stop services 
df -TH > mounted_fs
systemctl list-units \
  --type=service \
  --state=running \
  --no-pager \
  --no-legend \
  | awk '!/ssh/ {print $1}' \
  | xargs systemctl stop

# Stop DNS from breaking
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# Copy old root to tmpfs
umount -a
mkdir /tmp/tmproot
mount none /tmp/tmproot -t tmpfs
mkdir /tmp/tmproot/{proc,sys,usr,var,run,dev,tmp,home,oldroot}
cp -ax /{bin,etc,mnt,sbin,lib,lib64} /tmp/tmproot/
cp -ax /usr/{bin,sbin,lib,lib64} /tmp/tmproot/usr/
cp -ax /var/{lib,local,lock,opt,run,spool,tmp} /tmp/tmproot/var/
cp -Rax /home /tmp/tmproot/

# Copy new image to tmpfs
wget https://geo.mirror.pkgbuild.com/images/v20230301.130409/Arch-Linux-x86_64-cloudimg.qcow2 \
  -P /tmp/tmproot

# Download Arch Linux cloud image
modprobe nbd max_part=8; sleep 1
qemu-nbd --connect=/dev/nbd0 /tmp/tmproot/Arch-Linux-x86_64-cloudimg.qcow2; sleep 1
mount /dev/nbd0p2 /mnt; sleep 1
# Do stuff on the image

Cleanup
umount /mnt
qemu-nbd --disconnect /dev/nbd0
rmmod nbd

# Switch root to tmpfs
mount --make-rprivate /
pivot_root /tmp/tmproot /tmp/tmproot/oldroot

# Move system mounts to tmpfs
for i in dev proc sys run; do mount --move /oldroot/$i /$i; done
# Restart services within the ramroot
systemctl restart sshd
systemctl list-units \
  --type=service \
  --state=running \
  --no-pager \
  --no-legend \
  | awk "!/ssh/ {print \$1}" \
  | xargs systemctl restart
systemctl daemon-reexec
# Create the service unit file
sudo tee /etc/systemd/system/reimage.service <<EOF
[Unit]
Description=My Job

[Service]
Type=oneshot
ExecStart=/bin/bash -c "fuser -vkm /oldroot && umount -l /oldroot/ && qemu-img convert -f qcow2 -O raw /Arch-Linux-x86_64-cloudimg.qcow2 /dev/vda && reboot"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start reimage