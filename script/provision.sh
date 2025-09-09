#! /bin/bash
set -ex

# Install kernel packages.
dpkg -i /mnt/root/linux*.deb

# We'll use /sbin/init as init system (this will be configured via kernel boot
# args).
if [ ! -e /sbin/init ]; then
    ln -sf /usr/lib/systemd/systemd /sbin/init
fi

# ubuntu will be the user that will run GitHub Actions and anything else that
# needs doing on the guest.
useradd -m -s /bin/bash ubuntu
passwd -d ubuntu
passwd -d root
usermod -aG sudo ubuntu
sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' /etc/ssh/sshd_config
echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config

# # This prevents systemd from waiting for ttyS0 device (we pass console via kernel boot args)
systemctl mask serial-getty@ttyS0.service

# All the other packages are installed via debootstrap, but this one was could
# not be installed that way.
apt-get update 
apt-get install -y dnsutils

# https://github.com/firecracker-microvm/firecracker/blob/8208ee8ca0ab6e43fe0c22a7d9cb41b5045d4ef4/resources/chroot.sh#L49
rm -f /etc/systemd/system/multi-user.target.wants/systemd-resolved.service
rm -f /etc/systemd/system/dbus-org.freedesktop.resolve1.service
rm -f /etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service


# https://github.com/firecracker-microvm/firecracker/blob/8208ee8ca0ab6e43fe0c22a7d9cb41b5045d4ef4/resources/chroot.sh#L67-L69
ln -s /dev/null /etc/systemd/network/99-default.link

# https://github.com/firecracker-microvm/firecracker/blob/8208ee8ca0ab6e43fe0c22a7d9cb41b5045d4ef4/resources/chroot.sh#L67-L69 
systemctl disable e2scrub_reap.service
rm -vf /etc/systemd/system/timers.target.wants/*

# https://github.com/firecracker-microvm/firecracker/blob/8208ee8ca0ab6e43fe0c22a7d9cb41b5045d4ef4/resources/chroot.sh#L67-L69
rm -rf /usr/share/{doc,man,info,locale}

# Install GitHub Actions runner.
cd /home/ubuntu
curl -o actions-runner-linux-x64-${GITHUB_ACTIONS_RUNNER_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${GITHUB_ACTIONS_RUNNER_VERSION}/actions-runner-linux-x64-${GITHUB_ACTIONS_RUNNER_VERSION}.tar.gz
tar xzf ./actions-runner-linux-x64-${GITHUB_ACTIONS_RUNNER_VERSION}.tar.gz
chown -R ubuntu:ubuntu /home/ubuntu
rm actions-runner-linux-x64-${GITHUB_ACTIONS_RUNNER_VERSION}.tar.gz

echo "fc-ubuntu" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
127.0.1.1   fc-ubuntu
EOF

# Make /etc/resolv.conf a link so that nameservers can be configured via kernel boot args.
# https://github.com/firecracker-microvm/firecracker/issues/5172
rm -rf /etc/resolv.conf
ln -s /proc/net/pnp /etc/resolv.conf
