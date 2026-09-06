# KUBESPRAY_SETUP_ANALYSIS.md

## Project Overview

This project is already set up with Kubespray, an open source Kubernetes deployment tool that automates the installation of a production-ready Kubernetes cluster on bare metal or virtual machines.

The current implementation:
- Is designed for a single Master and single Worker node
- Has hardcoded IPs and SSH user in setup-kubernetes.sh 
- Uses standard Kubespray inventory structure with [kube_control_plane], [etcd], [kube_node] groups  
- Does not support multiple masters or flexible SSH key configuration

## Current Issues

1. **Hardcoded Values**: Master IP (192.168.88.140) and Worker IP (192.168.88.141) are hardcoded
2. **Single SSH Key**: Uses default ssh_user but doesn't support different keys per node
3. **Limited Scale**: Only 1 master + 1 worker supported
4. **No Configurable Node Names**: Hostnames/aliases are not configurable in inventory

## Kubespray Inventory Structure

From inspection:
- Group structure needed: kube_control_plane, etcd, kube_node 
- Ansible host configuration supports individual SSH configuration via variables in hosts.ini
- Can use `ansible_ssh_private_key_file` for specifying private key per host

Example of per-host inventory with keys:
```
[node1]
master1 ansible_host=192.168.88.140 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/master1_key
[node2] 
worker1 ansible_host=192.168.88.141 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/worker1_key
```

## Analysis Results

### Key Findings:
- Kubespray version is installed with Ansible 2.18.x requirement (current system has 2.21.3, which causes compatibility issues)
- Current configuration: Single master-node controlplane + single worker
- The inventory can support multiple masters through the `[kube_control_plane]` group 
- Multiple masters are supported by having all control plane nodes in that group
- The etcd group should include all members of kube_control_plane for HA 
- SSH per-host variable configuration can be done using `ansible_ssh_private_key_file`

### Required Changes:
1. Remove hardcoded IPs from setup-kubernetes.sh
2. Allow dynamic master/worker node definitions via external config file
3. Support flexible SSH user and key mapping per node
4. Generate correct Kubespray inventory dynamically 
5. Handle validation and connectivity tests for multiple nodes
6. Maintain compatibility with existing Kubespray mechanisms

### Technical Approach:
1. YAML-based configuration file to define masters/workers  
2. Create dynamic hosts.ini based on the config
3. Support per-node ansible_ssh_private_key_file mapping 
4. Validate configurations before deployment
5. Support dry-run and validation modes
6. Integrate with existing Kubespray inventory system
