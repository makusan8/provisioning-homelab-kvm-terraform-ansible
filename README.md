# Provisioning KVM with Terraform & Ansible

## Intro

Step by step how to provision a KVM virtual machines using Terraform & Ansible. At later part we will incorporate Kubernetes k3s/k8s on top of it.

This write up is going to be a multi part series. (still ongoing)

## Preparing our Host with KVM

I'll be using Debian 12 (minimal) as my Host VM, you can refer to here how it's installed :

https://github.com/makusan8/kubernetes

Now, let's start :-)

### Part 1. Install KVM (libvirt)


