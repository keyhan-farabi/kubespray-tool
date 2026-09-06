# Kubespray Kubernetes Cluster Setup

## Cluster Architecture

This setup can create flexible Kubernetes cluster using Kubespray:

### Single Master (Default)
```
Kubernetes Cluster
│
├── 192.168.88.140
│   ├── Control Plane
│   └── etcd
│
└── 192.168.88.141
    └── Worker
```

### Multi-Master Configuration (Advanced)
Supports multiple masters with HA etcd clustering

## Deployment Instructions

This setup uses the existing Kubespray repository at `/home/ubuntu/Desktop/kubespray/kubespray`.

### Prerequisites

- Ansible installed (version 2.18.x recommended) - Note: System currently has 2.21.3 incompatible with Kubespray
- SSH access to nodes with user `ubuntu`
- Internet connectivity on all nodes
- Existing Kubespray installation

### Configuration

A YAML configuration file (`cluster-config.yaml`) defines the cluster topology:

**Example Configuration:**
```yaml
masters:
  - name: master-1
    ip: 192.168.88.140
    ssh_user: ubuntu
    ssh_key: ~/.ssh/master1_key

  - name: master-2  
    ip: 192.168.88.142
    ssh_user: ubuntu
    ssh_key: ~/.ssh/master2_key

workers:
  - name: worker-1
    ip: 192.168.88.141
    ssh_user: ubuntu
    ssh_key: ~/.ssh/worker1_key

  - name: worker-2
    ip: 192.168.88.143
    ssh_user: ubuntu  
    ssh_key: ~/.ssh/worker2_key
```

### Deployment Commands (New)
Using the enhanced script:
```bash
# Dry-run to validate configuration only
./setup-kubernetes.sh --config cluster-config.yaml --dry-run

# Actual deployment 
./setup-kubernetes.sh --config cluster-config.yaml
```

For manual deployment with compatible Ansible version:
```bash
cd /home/ubuntu/Desktop/kubespray/kubespray
ansible-playbook -i inventory/mycluster/hosts.ini cluster.yml -b --flush-cache
```

### Testing Cluster

After deployment, verify with:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info
```

Nodes should show as `Ready` status.

### Test Deployment

Deploy a test workload:

```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80
kubectl get deployment
kubectl get pods -o wide
kubectl get svc
```

Clean up after testing:
```bash
kubectl delete deployment nginx
kubectl delete service nginx
```

## Reset/Destroy Instructions

To reset the cluster:
```bash
cd /home/ubuntu/Desktop/kubespray/kubespray
ansible-playbook -i inventory/mycluster/hosts.ini reset.yml -b --flush-cache
```

## Known Issues and Workarounds

Due to Ansible version compatibility issues (current system has Ansible 2.21.3, but Kubespray requires between 2.18.0 and 2.19.0), the actual deployment cannot be completed as part of this script execution.

The automation script creates the inventory correctly and validates configurations, but the actual deployment must be done separately with a compatible Ansible version.