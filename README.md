# Provisioning KVM with Terraform & Ansible

## Intro

Step by step how to provision a KVM virtual machines using Terraform & Ansible. At later part we will incorporate Kubernetes k3s/k8s on top of it.

This write up is going to be a multi part series. (still ongoing)

## Preparing our Host with KVM

I'll be using Debian 12 (minimal) as my Host VM, you can refer to here (until part 2) how the base is installed :

https://github.com/makusan8/single-vm-kubernetes

Now, let's start :-)

### Part 1. Install KVM (libvirt)

- Install libvirt with bridge-utils

```
# download (around 200+mb)
sudo nala install -y qemu-kvm \
libvirt-daemon-system \
libvirt-daemon virtinst bridge-utils \
libosinfo-bin gpg curl wget \
mkisofs
```

- Enable virtual host

```
sudo modprobe vhost_net
sudo echo vhost_net | sudo tee -a /etc/modules
```

- Add user to libvirt group

```
# show which group for libvirt
getent group | grep libvirt

# add current user to the group
sudo usermod -aG libvirt,libvirt-qemu $(whoami)

# reload group
newgrp libvirt
newgrp libvirt-qemu

# verify current group
id -nG
```

- Edit libvirtd, qemu config files

```
# backup config files
sudo cp /etc/libvirt/libvirtd.conf /etc/libvirt/libvirtd.conf.orig

sudo cp /etc/libvirt/qemu.conf /etc/libvirt/qemu.conf.orig

# add this options into libvirtd.conf
sudo cat << EOF >> /etc/libvirt/libvirtd.conf
unix_sock_group = "libvirt"
unix_sock_rw_perms = "0770"
EOF

# also for qemu.conf
sudo cat << EOF >> /etc/libvirt/qemu.conf
user = "libvirt-qemu"
group = "libvirt"
security_driver = "none"
EOF
```

- Enable libvirtd services

```
# start libvirtd
sudo systemctl enable --now libvirtd
```

- Verify access to qemu (wrapper for kvm)
- Be noted that, there are 2 environments for virsh, one for root and another one for our user

```
# show qemu version
virsh -c qemu:///system version

Using library: libvirt 9.0.0
Using API: QEMU 9.0.0
Running hypervisor: QEMU 7.2.5

# using with sudo
sudo virsh -c qemu:///system version
```

### Part 2. Setting up Bridge Mode (internet access)

- On my host, i only have 1 network interface ens32 which is connected to the internet. We can convert this interface as a bridge for our Guest's VM.
- Configuring bridge mode

```
# determine which network interfaces you have
# mine is ens32
ip a

1: lo:
2: ens32:

# backup our config
sudo cp /etc/network/interfaces /etc/network/interfaces.orig

# disable current ens32, add br0 interface.
# just comment out the current interface.
# set br0 (dhcp) to ens32 as master.
# to set as static ip, you can refer to internet for additional settings

sudo vim /etc/network/interfaces

 # The primary network interface
 # allow-hotplug ens32
 # iface ens32 inet dhcp

 # Bridge
 auto br0
 iface br0 inet dhcp
 bridge_ports ens32
```

- If you're done, then reboot

```
sudo reboot

# after reboot, check br0 interface and see if it still can connect to the internet

ip a | grep br0
ping -c1 www.google.com
```

### Part 3. (Optional) Test run Guest VM

This part is optional, you can skip it. I just want to show you how to manually install a guest vm and it's gonna take some time and bandwidth too

- Create a new vm (debian), or use other OS
- The process here is just like how you fresh install a normal OS manually, set root passwd, select packages etc

```
# install from net-installer
sudo virt-install \
--name deb12 \
--ram 1024 \
--vcpus 1 \
--disk path=/var/lib/libvirt/images/deb12.qcow2,size=10 \
--os-variant debian11 \
--network bridge=br0 \
--graphics none \
--console pty,target_type=serial \
--location 'http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/' \
--extra-args 'console=ttyS0,115200n8 serial'
```

- After done installing the OS

```
# check our new vm
virsh list --all
virsh -c qemu:///system list

 Id   Name    State
-----------------------
 2    deb12   running

# access the vm from console, test login as root
virsh -c qemu:///system console deb12

Debian GNU/Linux 12 debian ttyS0
deb12 login: root
Password:
```

- Remove VM

```
# shutdown vm
virsh shutdown debian-vm

# remove vm
virsh undefine --domain deb12 --remove-all-storage
```

# Terraform

### Part 4. Installing Terraform



