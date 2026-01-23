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

# Ensure DNS works during provisioning by adding a fallback nameserver
# (systemd-resolved may not be fully functional in chroot environment)
# https://wiki.archlinux.org/title/Chroot
if ! grep -q nameserver /etc/resolv.conf 2>/dev/null; then
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
fi

# dnsutils seemed to be needed for DNS resolution to work at all
# nfs-common so that we can use Go module cache over NFS https://github.com/tailscale/gomodfs
# Set up Docker repo.
# Docker, build-essential,jq are needed for CI tests.
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y dnsutils nfs-common docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin build-essential jq postgresql postgresql-contrib

usermod -aG docker ubuntu

# nftables based implementation seems to hit a kernel issue during build.
update-alternatives --set iptables /usr/sbin/iptables-legacy

# Enable and start Docker service
systemctl enable docker
systemctl start docker

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf awscliv2.zip aws

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
mkdir -p /home/ubuntu/actions-runner
pushd /home/ubuntu/actions-runner
curl -o actions-runner-linux-x64-${GITHUB_ACTIONS_RUNNER_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${GITHUB_ACTIONS_RUNNER_VERSION}/actions-runner-linux-x64-${GITHUB_ACTIONS_RUNNER_VERSION}.tar.gz
tar xzf ./actions-runner-linux-x64-${GITHUB_ACTIONS_RUNNER_VERSION}.tar.gz
chown -R ubuntu:ubuntu /home/ubuntu/actions-runner
rm actions-runner-linux-x64-${GITHUB_ACTIONS_RUNNER_VERSION}.tar.gz

cat > /home/ubuntu/on-job-started.sh <<'EOF'
#!/usr/bin/env bash
if [ -n "$GH_STATE_TRANSITION_SERVER_ADDR" ]; then
  env -0 | curl --silent -X POST -H "Content-Type: text/plain" --data-binary @- "$GH_STATE_TRANSITION_SERVER_ADDR"
fi
EOF

chmod +x /home/ubuntu/on-job-started.sh

echo "ACTIONS_RUNNER_HOOK_JOB_STARTED=/home/ubuntu/on-job-started.sh" >> .env

chown -R ubuntu:ubuntu /home/ubuntu
popd

echo "fc-ubuntu" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
127.0.1.1   fc-ubuntu
EOF

# Install Nix package manager for the ubuntu user (before breaking DNS)
sudo -u ubuntu HOME=/home/ubuntu sh -c 'curl -L https://nixos.org/nix/install | sh -s -- --no-daemon --yes'
echo 'if [ -e /home/ubuntu/.nix-profile/etc/profile.d/nix.sh ]; then . /home/ubuntu/.nix-profile/etc/profile.d/nix.sh; fi' >> /home/ubuntu/.bashrc
chown ubuntu:ubuntu /home/ubuntu/.bashrc

# TODO: Automatically read hashes from nix/source.json in corp.
for hash in \
  61308fbb163ae7045c9b3004a0d067822984df33 \
  4989a246d7a390a859852baddb1013f825435cee \
  27bd67e55fe09f9d68c77ff151c3e44c4f81f7de \
  d19cf9dfc633816a437204555afeb9e722386b76; do
  nix-prefetch-url --unpack "https://github.com/NixOS/nixpkgs/archive/${hash}.tar.gz"
done

# Make /etc/resolv.conf a link so that nameservers can be configured via kernel boot args.
# https://github.com/firecracker-microvm/firecracker/issues/5172
rm -rf /etc/resolv.conf
ln -s /proc/net/pnp /etc/resolv.conf

# for some specific CI tests that need to distinguish Firecracker from other
# runners.
touch /home/ubuntu/.is-ephemeral-build-vm
