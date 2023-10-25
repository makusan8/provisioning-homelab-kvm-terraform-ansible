# main.tf

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

data "template_file" "user_data" {
  template = file("user-data.yaml")
}

resource "libvirt_cloudinit_disk" "cloud-init" {   
  name = "cloud-init.iso"
  user_data = data.template_file.user_data.rendered
}

resource "libvirt_domain" "debian-vm" {
  name = "debian-vm"
  memory = "1024"
  vcpu = 1

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
  
  network_interface {
    network_name = "default"
  }
}