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
mkisofs unzip
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
# verify that you have access to libvirt
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

# Provisioning with Terraform

If you wondered why we did the part 3 above, it's because the process to bring up the VMs which can be tedious and time consuming. Imagine if we need to setup 10 or more VMs? This is where Terraform comes into play.

Terraform is an Infrastruce As a Code (IAC), which means we can provision or automate our infra more easily by laying out it's foundation and ready to be consumed for other services or platforms. It supports a bunch of providers for example KVM, Proxmox, Vmware but more focused on the Cloud like AWS, Azure, GoogleCloud etc.

### Part 4. Installing & Configuring Terraform

- Before we start, it's better to create another storage-pool for kvm. Terraform can only know the pool from root enviroment, in this case we need to use sudo. 

```
# create a new directory
sudo mkdir -p /media/virtual-machines

# define the new dir
sudo virsh pool-define-as --name default --type dir --target /media/virtual-machines

# show current pool
# if you don't specify sudo, you'll get different value
sudo virsh pool-list --all

 Name      State      Autostart  
---------------------------------
 default   inactive   no
 images    active     yes

# activate the new default pool
sudo virsh pool-build default
sudo virsh pool-start default
sudo virsh pool-autostart default

# see more info
sudo virsh pool-info default

# restart libvirtd 
sudo systemctl restart libvirtd
```

- Download Cloud image, they a bit differrent from normal ISO image that we usually use (reduced in size).

```
# download debian12 qcow2 image
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2

# move the image
sudo mkdir -p /media/virtual-machines/sources
sudo mv debian-12-genericcloud-amd64.qcow2 /media/virtual-machines/sources/
```

- Install Terraform

```
# add key and install
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo nala update && sudo nala install terraform
```

- Now, We're ready for configuration part
- In order for terraform to access libvirt, we need the terraform-libvirt provider

```
# create dir
cd ~/
mkdir terraform && cd !$

# configure our main tf
vim main.tf
```

```
### main.tf
terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}
```

```
# run terraform init, this will download the libvirt provider
terraform init

Initializing provider plugins...
- Finding dmacvicar/libvirt versions matching "0.7.4"...
- Installing dmacvicar/libvirt v0.7.4...
```

- Noticed the provider "libvirt" above in our main.tf? That's how we tell terraform to connect to this specific provider. Other providers can be differrent.

- Next thing, we need to add disk volume
- Continue to edit main.tf 

```
# -- add after from above section

# add volume disk qcow2
resource "libvirt_volume" "debian-disk" {
  name = "debian-qcow2"
  pool = "default"
  source = "/media/virtual-machines/sources/debian-12-genericcloud-amd64.qcow2"
  format = "qcow2"
}
```

- This will use the source image as a base and create a new disk volume for our VM

- Let's see this in action, run the commands below

```
# plan and apply our configuration
terraform plan -out terraform.out
terraform apply terraform.out
```

```
# this will give more details about what have been applied or created
terraform show

# libvirt_volume.debian-disk:
resource "libvirt_volume" "debian-disk" {
    format = "qcow2"
    id     = "/media/virtual-machines/debian-qcow2"
    name   = "debian-qcow2"
    pool   = "default"
    size   = 2147483648
    source = "/media/virtual-machines/sources/debian-12-genericcloud-amd64.qcow2" 
}
```

```
# check our default pool
sudo virsh -c qemu:///system vol-list default

 Name           Path
---------------------------------------------------
 debian-qcow2   /media/virtual-machines/debian-qcow2
 sources        /media/virtual-machines/sources
```

- Next, we can define our domain which is kind of specifications for our VM like cpu, memory, disk etc

- Before we proceed and apply our new configuration, we have to destroy the previous applied volume
- Always! destroy -> plan -> apply

```
# destroy
terraform destroy

Destroy complete! Resources: 2 destroyed.
```

- Add domain section, edit in main.tf

```
# VM specifications
resource "libvirt_domain" "debian-vm" {
  name = "debian-vm"
  memory = "1024"
  vcpu = 1

  disk {
    volume_id = libvirt_volume.debian-disk.id
  }

  console {
    target_type = "serial"
    type = "pty"
    target_port = "0"
  }
  console {
    target_type = "virtio"
    type = "pty"
    target_port = "1"
  }
}
```

- Apply the new configuration again

```
terraform plan -out terraform.out
terraform apply terraform.out
```

- Verify via virsh, access with console

```
# check if our is running
sudo virsh -c qemu:///system list

 Id   Name        State
---------------------------
 2    debian-vm   running
```

```
# access the console, you'll be prompted for login
sudo virsh -c qemu:///system console debian-vm

Connected to domain 'debian-vm'
Escape character is ^] (Ctrl + ])

debian-vm login:
```

- We're almost done, however how do we login? We don't set any login & password yet, Ouch!

- Cloud-init to the rescue, we can actually supply or inject a user data variable during the apply process. Let's set it up

```
# destroy again
terraform destroy -auto-approve
```

```
# create user-data.yaml
vim user-data.yaml
```

- Add this below in user-data.yaml

```
#cloud-config

disable_root: false
chpasswd:
  list: |
       root:123
  expire: False

# Set TimeZone
timezone: Asia/Kuala_Lumpur

hostname: debian12-vm

growpart:
  mode: auto
  devices: ['/']

# PostInstall
runcmd:
```

- Define cloud init disk and load user-data.yml template in main.tf
- There are 3 parts that we need to add

```
# 1. load user-data
data "template_file" "user_data" {
  template = file("user-data.yaml")
}

# 2. supply user data into cloud-init iso
resource "libvirt_cloudinit_disk" "cloud-init" {   
  name = "cloud-init.iso"
  user_data = data.template_file.user_data.rendered
}

# 3. load cloud-init iso (inside libvirt_domain)
cloudinit = libvirt_cloudinit_disk.cloud-init.id

```

- Our updated main.tf gonna looks like this

```
### main.tf

terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

resource "libvirt_volume" "debian-disk" {
  name = "debian-qcow2"
  pool = "default"
  source = "/media/virtual-machines/sources/debian-12-genericcloud-amd64.qcow2"   
  format = "qcow2"
}

# 1. load user-data
data "template_file" "user_data" {
  template = file("user-data.yaml")
}

# 2. supply user data into cloud-init iso
resource "libvirt_cloudinit_disk" "cloud-init" {   
  name = "cloud-init.iso"
  user_data = data.template_file.user_data.rendered
}

resource "libvirt_domain" "debian-vm" {
  name = "debian-vm"
  memory = "1024"
  vcpu = 1

  # 3. load cloud-init iso
  cloudinit = libvirt_cloudinit_disk.cloud-init.id

  disk {
    volume_id = libvirt_volume.debian-disk.id
  }

  console {
    target_type = "serial"
    type = "pty"
    target_port = "0"
  }
  console {
    target_type = "virtio"
    type = "pty"
    target_port = "1"
  }
}
```

- Plan and re-apply our new configuration
- During the plan (important!), you'll noticed there is user_data = <<-EOT being injected like below, if you're not seeing this, check your configuration again


```
# plan 
terraform plan -out terraform.out

# libvirt_cloudinit_disk.cloud-init will be created
  + resource "libvirt_cloudinit_disk" "cloud-init" {
      + id        = (known after apply)
      + name      = "cloud-init.iso"
      + pool      = "default"
      + user_data = <<-EOT
            #cloud-config
            disable_root: false
            chpasswd:
              list: |
                root:123
              expire: False

            timezone: Asia/Kuala_Lumpur

            hostname: "debian12-vm"

            growpart:
              mode: auto
              devices: ['/']
  }

# apply
terraform apply terraform.out
```

- Access the vm via console and try to login with what we set in user-data.yaml

```
# access the console and login
sudo virsh -c qemu:///system console debian-vm

debian12-vm login: root
Password: 

Linux debian12-vm 6.1.0-13-cloud-amd64 ...
root@debian12-vm:~#

# logout from vm
exit
ctrl + ]
```

```
# destroy again
terraform destroy -auto-approve
```

- Finally our VM is almost ready, but we're still missing the network and thus have no connection to the internet
- Let's add the last missing part, network

```
# in main.tf - libvirt domain section, just below console

    console {
        target_type = "virtio"
        type = "pty"
        target_port = "1"
    }

    # add this network
    network_interface {
        network_name = "default"
    }
```

- Verify our network, it appears the default is not activated yet

```
# verify
sudo virsh net-list --all

 Name      State      Autostart   Persistent
----------------------------------------------
 default   inactive   no          yes
```

```
# start the default network
sudo virsh net-start default
sudo virsh net-autostart default
```

```
# show the default settings
sudo virsh net-dumpxml default

<network connections='1'>
  <name>default</name>
  <uuid>c56c2c8c-b020-43d6-a4dc-dc5a01dfad5a</uuid>       
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='virbr0' stp='on' delay='0'/>
  <mac address='52:54:00:e7:4c:4c'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>    
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
```

- Recalled the bridge mode that we set up earlier in Part 2? This will be use for our VM's network connection and as for now we don't have to change anything on it

- Lastly, Start VM, login and test the connection again

```
terraform plan -out terraform.out
terraform apply terraform.out
```

```
root@debian12-vm:~# ping -c1 www.google.com
PING www.google.com (142.251.223.68) 56(84) bytes of data.
64 bytes from kul09s21-in-f4.1e100.net (142.251.223.68): icmp_seq=1 ttl=127 time=31.2 ms

--- www.google.com ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 31.190/31.190/31.190/0.000 ms
```




