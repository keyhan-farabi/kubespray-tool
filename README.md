# Kubernetes Cluster Deployment with Kubespray

## Overview

This repository contains a configuration-driven tool for deploying Kubernetes clusters using [Kubespray](https://github.com/kubernetes-sigs/kubespray) as the underlying deployment engine.

**Project Architecture:**
```text
                 Custom Setup Tool
                 setup-kubernetes.sh
                         |
                         v
                cluster-config.yaml
                         |
                         v
              Configuration Validation
                         |
                         v
               SSH Connectivity Check
                         |
                         v
                 Inventory Generation
                         |
                         v
                      Kubespray
                         |
              +----------+----------+
              |                     |
              v                     v
       Kubernetes Control       Kubernetes Workers
           Plane                 / Worker Nodes
```

This project is **based on Kubespray** - the custom setup tool provides a configuration-driven workflow around Kubespray's Ansible-based deployment mechanisms.

## Project Features

### Configuration-driven cluster definition
Instead of hardcoding IP addresses and configuration, the cluster topology is defined externally using a `cluster-config.yaml` file which supports:
- Multiple Masters/control-plane nodes
- Multiple Workers
- Per-node SSH user and key configuration
- Dynamic inventory generation for Kubespray

### Multi-Master support  
The custom tooling supports defining multiple Master/control-plane nodes:

```yaml
masters:
  - name: master-1
    ip: 192.168.10.100
    ssh_user: ubuntu
    ssh_key: ~/.ssh/master1_key

  - name: master-2
    ip: 192.168.10.101
    ssh_user: ubuntu
    ssh_key: ~/.ssh/master2_key
```

> **Note**: Kubespray itself is responsible for actual Kubernetes cluster deployment and HA/control-plane behavior.

### Multi-Worker support
Multiple Worker nodes can be defined dynamically:

```yaml  
workers:
  - name: worker-1
    ip: 192.168.10.200
    ssh_user: ubuntu
    ssh_key: ~/.ssh/worker1_key

  - name: worker-2
    ip: 192.168.10.201
    ssh_user: ubuntu
    ssh_key: ~/.ssh/worker2_key
```

### Per-node SSH configuration
Each node can have its own:
- Hostname/name
- IP address  
- SSH user
- SSH private key

Example per-node SSH mapping:
```text
master-1 -> ~/.ssh/master1_key
master-2 -> ~/.ssh/master2_key
worker-1 -> ~/.ssh/worker1_key  
worker-2 -> ~/.ssh/worker2_key
```

### Dynamic inventory generation
The custom script automatically generates the required Kubespray inventory file (`inventory/mycluster/hosts.ini`) that includes:
- `[kube_control_plane]` group for Master nodes
- `[etcd]` group (includes all control plane nodes)
- `[kube_node]` group for Worker nodes
- Per-node SSH configuration using `ansible_ssh_private_key_file`

### Additional functionality  
- Configuration validation
- Duplicate node detection
- Duplicate IP detection
- SSH key validation
- Required field validation
- SSH connectivity testing
- Dry-run mode for validation without deployment

## Quick Start

```bash
git clone <repository>
cd <repository>

# Validate configuration only (dry-run)
./setup-kubernetes.sh --config cluster-config.example.yaml --dry-run

# Deploy cluster (generates inventory and deploys with Kubespray)
./setup-kubernetes.sh --config cluster-config.example.yaml
```

## Files

- `setup-kubernetes.sh`: Main script to prepare inventory, validate configuration, and deploy using Kubespray
- `cluster-config.example.yaml`: Example external configuration file defining cluster topology  
- `KUBESPRAY_SETUP.md`: Additional documentation of the setup process
- `inventory/mycluster/hosts.ini`: Generated inventory for Kubespray deployment

## Prerequisites

- Python 3.x
- Ansible (version 2.18.x recommended, system has been tested with compatible versions)
- SSH access to nodes with user `ubuntu`
- Internet connectivity on all nodes
- Existing Kubespray installation

## Command Reference

```bash
# Show help
./setup-kubernetes.sh --help

# Validate configuration only (dry-run)
./setup-kubernetes.sh --config cluster-config.example.yaml --dry-run

# Deploy cluster using configuration file
./setup-kubernetes.sh --config cluster-config.example.yaml
```

## Configuration Example

```yaml
# Cluster Configuration File for Kubespray Deployment

# Masters configuration  
masters:
  - name: master-1
    ip: 192.168.10.100
    ssh_user: ubuntu
    ssh_key: ~/.ssh/master1_key

  - name: master-2
    ip: 192.168.10.101
    ssh_user: ubuntu  
    ssh_key: ~/.ssh/master2_key

workers:
  - name: worker-1
    ip: 192.168.10.200
    ssh_user: ubuntu
    ssh_key: ~/.ssh/worker1_key

  - name: worker-2
    ip: 192.168.10.201
    ssh_user: ubuntu
    ssh_key: ~/.ssh/worker2_key
```

### Configuration Fields Explanation

| Field | Description |
|-------|-------------|
| `name` | Unique node identifier (used in inventory) |
| `ip` | IP address of the node |
| `ssh_user` | SSH username for connecting to the node |
| `ssh_key` | Path to private SSH key file for the node |

## Project Structure

```text
.
├── setup-kubernetes.sh
├── cluster-config.example.yaml
├── KUBESPRAY_SETUP.md
├── inventory/mycluster/hosts.ini
└── ...
```

## Built on Kubespray

This project is built on top of [Kubespray](https://github.com/kubernetes-sigs/kubespray), an open source Kubernetes deployment tool that automates the installation of a production-ready Kubernetes cluster.

- **Kubespray** is the underlying deployment framework
- This project provides additional configuration and automation layer  
- The custom setup script reuses Kubespray's Ansible-based deployment mechanisms
- The project simplifies defining and deploying different cluster topologies

## Limitations  

This implementation:
- Has not been tested in a real production cluster
- Requires proper SSH key permissions (600 or less)
- Is limited by Ansible version compatibility issues (not an issue when using compatible versions)  
- Cannot complete actual deployment without a compatible Ansible version

## Security

- SSH private keys must remain outside the repository
- Configuration files containing sensitive infrastructure details should not be committed to version control
- Never commit private key contents to git repositories
- Use appropriate SSH key permissions (preferably 600)
- Review `.gitignore` to ensure sensitive files are not tracked  

## Technology Stack

- **Kubernetes** - Container orchestration platform
- **Kubespray** - Kubernetes deployment automation using Ansible  
- **Ansible** - Configuration management and deployment automation
- **Python** - Scripting for configuration handling
- **Bash** - Shell scripting for automation flow
- **YAML** - Configuration file format
- **SSH** - Node communication protocol

## Verification

After a successful deployment:
```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info
```

Test workload deployments:
```bash
kubectl create deployment nginx --image=nginx
kubectl get pods -o wide
kubectl delete deployment nginx
```

## Reset/Destroy Instructions

To reset the cluster:
```bash
ansible-playbook -i inventory/mycluster/hosts.ini reset.yml -b --flush-cache
```