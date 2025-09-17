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

# dnsutils seemed to be needed for DNS resolution to work at all
apt-get update
apt-get install -y dnsutils

# Temporarily install Go to build go-tool-cache binary
GO_VERSION="1.25.0"
curl -L https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz | tar -xz -C /tmp
export GOROOT=/tmp/go
export PATH=/tmp/go/bin:$PATH
export GOPATH=/tmp/gopath
export GOTELEMETRY=off
/tmp/go/bin/go install github.com/bradfitz/go-tool-cache/cmd/go-cacher@latest
mv /tmp/gopath/bin/go-cacher /home/ubuntu/gocacheprog
chmod +x /home/ubuntu/gocacheprog
rm -rf /tmp/go /tmp/gopath

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
if [ -n "$GH_STATE_TRANSITION_SERVER_TOKEN" ] && [ -n "$GH_STATE_TRANSITION_SERVER_URL" ]; then
  ADDR="${GH_STATE_TRANSITION_SERVER_URL}?token=${GH_STATE_TRANSITION_SERVER_TOKEN}&state=started"
  env -0 | curl --silent -X POST -H "Content-Type: text/plain" --data-binary @- "$ADDR"
fi
EOF

cat > /home/ubuntu/on-job-completed.sh <<'EOF'
#!/usr/bin/env bash
if [ -n "$GH_STATE_TRANSITION_SERVER_TOKEN" ] && [ -n "$GH_STATE_TRANSITION_SERVER_URL" ]; then
  ADDR="${GH_STATE_TRANSITION_SERVER_URL}?token=${GH_STATE_TRANSITION_SERVER_TOKEN}&state=completed"
  env -0 | curl --silent -X POST -H "Content-Type: text/plain" --data-binary @- "$ADDR"
fi
EOF

chmod +x /home/ubuntu/on-job-started.sh
chmod +x /home/ubuntu/on-job-completed.sh

echo "ACTIONS_RUNNER_HOOK_JOB_STARTED=/home/ubuntu/on-job-started.sh" >> .env
echo "ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/home/ubuntu/on-job-completed.sh" >> .env
echo "GOCACHEPROG=/home/ubuntu/gocacheprog --gateway-addr-port=31364" >> .env

chown -R ubuntu:ubuntu /home/ubuntu
popd

echo "fc-ubuntu" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
127.0.1.1   fc-ubuntu
EOF

# Make /etc/resolv.conf a link so that nameservers can be configured via kernel boot args.
# https://github.com/firecracker-microvm/firecracker/issues/5172
rm -rf /etc/resolv.conf
ln -s /proc/net/pnp /etc/resolv.conf
