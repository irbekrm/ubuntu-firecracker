This is an experimental fork of https://github.com/bkleiner/ubuntu-firecracker that creates a Firecracker image with a GitHub Actions runner. The root filesystem is based on Ubuntu minimal 24.04.

# ubuntu-firecracker
Docker container to build a linux kernel and ext4 rootfs compatible with [firecracker](https://github.com/firecracker-microvm/firecracker).

## Usage
Build the container:
```shell
docker build -t ubuntu-firecracker .
```

Build the image:
```shell
docker run --privileged -it --rm -v $(pwd)/output:/output ubuntu-firecracker
```

```shell
# copy image and kernel
cp output/kernel ubuntu-vmlinux
cp output/rootfs.ext4 rootfs.ext4

truncate -s 8G rootfs.ext4
resize2fs rootfs.ext4

# launch firecracker

example configfile for a bridge networking setup:

```
{"boot-source":{"kernel_image_path":"/home/ubuntu/images/kernel","boot_args":"console=ttyS0 init=/sbin/init root=/dev/vda rw noapic reboot=k panic=2 pci=off acpi=off ip=192.168.100.2::192.168.100.1:255.255.255.0::eth0:off:8.8.8.8:8.8.4.4"},"drives":[{"drive_id":"rootfs","path_on_host":"/home/ubuntu/images/rootfs.ext4","is_root_device":true,"is_read_only":false}],"network-interfaces":[{"iface_id":"eth0","guest_mac":"06:00:C0:A8:64:02","host_dev_name":"tap0"}],"machine-config":{"vcpu_count":14,"mem_size_mib":30720}}
```

```
firecracker --config-file ./conf.json  --no-api --level debug
```

## Contributions
This project is actively looking for contributions/maintainers.
I (bkleiner) have stopped using firecracker a while ago.
