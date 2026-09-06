#!/usr/bin/env bash
set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBESPRAY_DIR="$SCRIPT_DIR"
CONFIG_FILE=""
DRY_RUN=false
HELP=false

# Configuration defaults and variables
declare -A MASTER_NODES
declare -A WORKER_NODES
SSH_USER_DEFAULT="ubuntu"

function print_help() {
    cat << EOF
Kubespray Cluster Deployment Tool

Usage: $0 [OPTIONS]

Options:
  --config FILE              Path to cluster configuration YAML file (required)
  --dry-run                  Validate configuration without deploying
  --help                     Show this help message

Example:
  $0 --config cluster-config.example.yaml
  $0 --config cluster-config.example.yaml --dry-run

Configuration file format:
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
EOF
}

function parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                HELP=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                print_help
                exit 1
                ;;
        esac
    done

    if [[ "$HELP" == true ]]; then
        print_help
        exit 0
    fi

    if [[ -z "$CONFIG_FILE" ]]; then
        echo "Error: Configuration file is required."
        print_help
        exit 1
    fi
}

function check_dependencies() {
    echo "Checking dependencies..."
    
    if ! command -v ansible &> /dev/null; then
        echo "Error: Ansible is not installed"
        exit 1
    fi

    if [ ! -d "$KUBESPRAY_DIR" ]; then
        echo "Error: Kubespray directory does not exist at $KUBESPRAY_DIR"
        exit 1
    fi
    
    # Check for yq if needed
    if ! command -v yq &> /dev/null; then
        echo "Warning: 'yq' command not found. YAML parsing might fail."
    fi
}

function load_config() {
    echo "Loading cluster configuration from $CONFIG_FILE"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: Configuration file does not exist at $CONFIG_FILE"
        exit 1
    fi

    # Validate YAML with yq if available
    if command -v yq &> /dev/null; then
        if ! yq eval '.' "$CONFIG_FILE" > /dev/null; then
            echo "Error: Invalid YAML in configuration file $CONFIG_FILE"
            exit 1
        fi
    else 
        # Basic syntax check with bash (not ideal but functional)
        echo "Warning: yq not found, skipping YAML validation"
    fi

    # Parse configuration using a simple approach for minimal dependencies  
    local master_count=0
    local worker_count=0
    
    # Reset arrays first
    declare -A MASTER_NODES
    declare -A WORKER_NODES
    
    echo "Reading configuration..."
    
    # Use temporary file approach to parse cleanly
    local temp_file=$(mktemp)
    cat "$CONFIG_FILE" > "$temp_file"

    # Process master nodes using sed/grep approach 
    echo "Reading masters configuration..."
    if grep -q "masters:" "$temp_file"; then
        # Extract master node entries
        local master_section=$(grep -A 100 "masters:" "$temp_file" | grep -B 100 "workers:" | head -n -1)
        # Process each line of master section for nodes 
        echo "$master_section" | while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*-\s*name:\s*(.*)$ ]]; then
                local name="${BASH_REMATCH[1]}"
                # Remove leading/trailing whitespace from name
                name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                MASTER_NODES["$name"]="initialized"
                master_count=$((master_count+1))
            elif [[ "$line" =~ ^[[:space:]]*ip:\s*(.*)$ ]]; then
                local ip="${BASH_REMATCH[1]}"
                ip=$(echo "$ip" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                # Store as part of the most recent master node
                local last_master_name=""
                for key in "${!MASTER_NODES[@]}"; do
                    if [[ "${MASTER_NODES[$key]}" == "initialized" ]]; then
                        last_master_name="$key"
                    fi
                done
                if [[ -n "$last_master_name" ]]; then
                    MASTER_NODES["$last_master_name"]+="#$ip"
                fi
            elif [[ "$line" =~ ^[[:space:]]*ssh_user:\s*(.*)$ ]]; then
                local user="${BASH_REMATCH[1]}"
                user=$(echo "$user" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                # Store as part of the most recent master node
                local last_master_name=""
                for key in "${!MASTER_NODES[@]}"; do
                    if [[ "${MASTER_NODES[$key]}" == "initialized" ]]; then
                        last_master_name="$key"
                    fi
                done
                if [[ -n "$last_master_name" ]]; then
                    MASTER_NODES["$last_master_name"]+="#$user"
                fi
            elif [[ "$line" =~ ^[[:space:]]*ssh_key:\s*(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                # Store as part of the most recent master node
                local last_master_name=""
                for key in "${!MASTER_NODES[@]}"; do
                    if [[ "${MASTER_NODES[$key]}" == "initialized" ]]; then
                        last_master_name="$key"
                    fi
                done
                if [[ -n "$last_master_name" ]]; then
                    MASTER_NODES["$last_master_name"]+="#$key"
                fi
            fi
        done
    fi

    echo "Reading workers configuration..."
    # Process worker nodes using sed/grep approach 
    if grep -q "workers:" "$temp_file"; then
        # Extract worker node entries  
        local worker_section=$(grep -A 100 "workers:" "$temp_file" | head -n -1)
        echo "$worker_section" | while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*-\s*name:\s*(.*)$ ]]; then
                local name="${BASH_REMATCH[1]}"
                # Remove leading/trailing whitespace from name
                name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                WORKER_NODES["$name"]="initialized"
                worker_count=$((worker_count+1))
            elif [[ "$line" =~ ^[[:space:]]*ip:\s*(.*)$ ]]; then
                local ip="${BASH_REMATCH[1]}"
                ip=$(echo "$ip" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                # Store as part of the most recent worker node
                local last_worker_name=""
                for key in "${!WORKER_NODES[@]}"; do
                    if [[ "${WORKER_NODES[$key]}" == "initialized" ]]; then
                        last_worker_name="$key"
                    fi
                done
                if [[ -n "$last_worker_name" ]]; then
                    WORKER_NODES["$last_worker_name"]+="#$ip"
                fi
            elif [[ "$line" =~ ^[[:space:]]*ssh_user:\s*(.*)$ ]]; then
                local user="${BASH_REMATCH[1]}"
                user=$(echo "$user" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                # Store as part of the most recent worker node
                local last_worker_name=""
                for key in "${!WORKER_NODES[@]}"; do
                    if [[ "${WORKER_NODES[$key]}" == "initialized" ]]; then
                        last_worker_name="$key"
                    fi
                done
                if [[ -n "$last_worker_name" ]]; then
                    WORKER_NODES["$last_worker_name"]+="#$user"
                fi
            elif [[ "$line" =~ ^[[:space:]]*ssh_key:\s*(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                # Store as part of the most recent worker node
                local last_worker_name=""
                for key in "${!WORKER_NODES[@]}"; do
                    if [[ "${WORKER_NODES[$key]}" == "initialized" ]]; then
                        last_worker_name="$key"
                    fi
                done
                if [[ -n "$last_worker_name" ]]; then
                    WORKER_NODES["$last_worker_name"]+="#$key"
                fi
            fi
        done
    fi
    
    # Clean-up temp file
    rm -f "$temp_file"

    echo "Found $master_count master nodes and $worker_count worker nodes"
}

function validate_config() {
    echo "Validating configuration..."
    
    # Check that we have at least one master node
    if [[ ${#MASTER_NODES[@]} -eq 0 ]]; then
        echo "Error: No master nodes defined in configuration"
        exit 1
    fi

    # Validate each master node
    local master_count=0
    for name in "${!MASTER_NODES[@]}"; do
        master_count=$((master_count+1))
        local data="${MASTER_NODES[$name]}"
        if [[ -z "$data" ]]; then
            echo "Error: Master node '$name' has incomplete configuration"
            exit 1 
        fi
        
        # Split the fields (ip|ssh_user|ssh_key)
        IFS='|' read -r ip user key <<< "$data"
        
        if [[ -z "$ip" ]] || [[ -z "$user" ]] || [[ -z "$key" ]]; then
            echo "Error: Master node '$name' missing required fields (ip, user, or key)"
            exit 1
        fi
        
        # Validate IP address format 
        if ! [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            echo "Error: Invalid IP address '$ip' for master node '$name'"
            exit 1
        fi
        
        # Validate SSH key path
        if [ ! -f "$key" ]; then
            echo "Error: SSH key file does not exist: $key"
            exit 1
        fi

        # Check SSH key permissions
        local perm=$(stat -c "%a" "$key")
        if [[ $perm =~ 0..[7531] ]]; then
            echo "Warning: SSH key has insecure permissions ($perm), should be 600 or less"
        fi
        
        echo "Master node '$name': IP=$ip, User=$user, Key=$key"
    done
    
    # Validate each worker node
    local worker_count=0
    for name in "${!WORKER_NODES[@]}"; do
        worker_count=$((worker_count+1))
        local data="${WORKER_NODES[$name]}"
        if [[ -z "$data" ]]; then
            echo "Error: Worker node '$name' has incomplete configuration"
            exit 1 
        fi
        
        # Split the fields (ip|ssh_user|ssh_key)
        IFS='|' read -r ip user key <<< "$data"
        
        if [[ -z "$ip" ]] || [[ -z "$user" ]] || [[ -z "$key" ]]; then
            echo "Error: Worker node '$name' missing required fields (ip, user, or key)"
            exit 1
        fi
        
        # Validate IP address format 
        if ! [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            echo "Error: Invalid IP address '$ip' for worker node '$name'"
            exit 1
        fi
        
        # Validate SSH key path
        if [ ! -f "$key" ]; then
            echo "Error: SSH key file does not exist: $key"
            exit 1
        fi

        # Check SSH key permissions  
        local perm=$(stat -c "%a" "$key")
        if [[ $perm =~ 0..[7531] ]]; then
            echo "Warning: SSH key has insecure permissions ($perm), should be 600 or less"
        fi
        
        echo "Worker node '$name': IP=$ip, User=$user, Key=$key"
    done
    
    echo "Configuration validation passed. Found $master_count masters and $worker_count workers."
}

function validate_ssh_connectivity() {
    echo "Testing SSH connectivity..."
    local all_passed=true
    
    # Test all master nodes
    for name in "${!MASTER_NODES[@]}"; do
        local data="${MASTER_NODES[$name]}"
        IFS='|' read -r ip user key <<< "$data"
        echo -n "[TESTING] $name ($ip) using $key... "
        
        if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
                -i "$key" "$user@$ip" exit &> /dev/null; then
            echo "[OK]"
        else
            echo "[FAILED]"
            all_passed=false
        fi
    done
    
    # Test all worker nodes  
    for name in "${!WORKER_NODES[@]}"; do
        local data="${WORKER_NODES[$name]}"
        IFS='|' read -r ip user key <<< "$data"
        echo -n "[TESTING] $name ($ip) using $key... "
        
        if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
                -i "$key" "$user@$ip" exit &> /dev/null; then
            echo "[OK]"
        else
            echo "[FAILED]"
            all_passed=false
        fi
    done
    
    if [[ "$all_passed" == false ]]; then
        echo "SSH connectivity test failed. Please check SSH keys and network access."
        exit 1
    fi
    
    echo "All SSH connections successful"
}

function generate_inventory() {
    echo "Generating Kubespray inventory..."
    
    # Create inventory directory if not exists
    mkdir -p "$KUBESPRAY_DIR/inventory/mycluster"
    
    # Start content of inventory file
    local inventory_content="# Generated Kubespray inventory
[kube_control_plane]
"
    
    # Add master nodes to control plane group  
    for name in "${!MASTER_NODES[@]}"; do
        local data="${MASTER_NODES[$name]}"
        IFS='|' read -r ip user key <<< "$data"
        inventory_content+="$name ansible_host=$ip ansible_user=$user ansible_ssh_private_key_file=$key
"
    done
    
    # Add etcd group (same as control plane for stacked etcd)
    inventory_content+="[etcd:children]
kube_control_plane

[kube_node]
"   
    
    # Add worker nodes to node group  
    for name in "${!WORKER_NODES[@]}"; do
        local data="${WORKER_NODES[$name]}"
        IFS='|' read -r ip user key <<< "$data"
        inventory_content+="$name ansible_host=$ip ansible_user=$user ansible_ssh_private_key_file=$key
"
    done

    # Add all:vars section
    inventory_content+="[all:vars]
ansible_become=true 
ansible_ssh_pipelining=true
loadbalancer_apiserver_localhost=true
loadbalancer_apiserver_type=nginx
"

    # Write final inventory file  
    echo "$inventory_content" > "$KUBESPRAY_DIR/inventory/mycluster/hosts.ini"
    
    echo "Inventory generated successfully."
    echo "Generated inventory content:"
    cat "$KUBESPRAY_DIR/inventory/mycluster/hosts.ini"
}

function validate_inventory() {
    echo "Validating generated inventory..."
    
    if [ ! -f "$KUBESPRAY_DIR/inventory/mycluster/hosts.ini" ]; then
        echo "Error: Generated inventory file not found"
        exit 1
    fi
    
    # Test with ansible-inventory
    echo -n "Testing Ansible inventory parser... "
    if ansible-inventory -i "$KUBESPRAY_DIR/inventory/mycluster/hosts.ini" --list > /dev/null 2>&1; then
        echo "[SUCCESS]"
    else
        echo "[FAILED]" 
        echo "Inventory validation failed."
        exit 1
    fi
    
    # Test connectivity to all nodes if not dry-run
    if [[ "$DRY_RUN" == false ]]; then
        echo -n "Testing Ansible connectivity... "
        if ansible all -i "$KUBESPRAY_DIR/inventory/mycluster/hosts.ini" -m ping --timeout 5 > /dev/null 2>&1; then 
            echo "[SUCCESS]"
        else
            echo "[FAILED]" 
            echo "Ansible connectivity test failed."
            exit 1
        fi
    else
        echo "Skipping live inventory validation in dry-run mode"
    fi
}

function prepare_virtualenv() {
    echo "Setting up virtual environment..."
    
    # Create and activate virtual environment if needed
    if [ ! -d "$KUBESPRAY_DIR/.venv" ]; then
        echo "Creating Python virtual environment..."
        python3 -m venv "$KUBESPRAY_DIR/.venv"
    fi

    echo "Activating virtual environment..."
    source "$KUBESPRAY_DIR/.venv/bin/activate"

    # Upgrade pip if needed
    pip install --upgrade pip

    # Install required dependencies
    echo "Installing Kubespray dependencies from requirements.txt..."
    if [ -f "$KUBESPRAY_DIR/requirements.txt" ]; then
        pip install -r "$KUBESPRAY_DIR/requirements.txt"
    else
        echo "Warning: requirements.txt not found, trying to install basic requirements"
        pip install ansible==11.13.0 
    fi

    # Verify Ansible version in virtual environment  
    echo "Checking Ansible version..."
    local ANSIBLE_VERSION=$(ansible --version | head -n1 | sed 's/.*\[\(.*\)\].*/\1/')
    echo "Active Ansible version: $ANSIBLE_VERSION"
}

function deploy_cluster() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "Dry run mode enabled. Skipping actual deployment."
        return
    fi

    echo "Starting Kubespray deployment..."
    echo "=================================="

    # Change to the Kubespray directory  
    cd "$KUBESPRAY_DIR"
    
    # Run a basic connectivity check to verify inventory is correct 
    echo "Testing playbook execution..."
    if [ -f "playbooks/cluster.yml" ]; then
        playbook_path="playbooks/cluster.yml"
    elif [ -f "cluster.yml" ]; then
        playbook_path="cluster.yml"
    else
        echo "Error: No cluster.yml found in expected locations!"
        exit 1
    fi

    # Execute the actual Kubespray deployment for the cluster  
    echo "Running ansible-playbook..."
    source "$KUBESPRAY_DIR/.venv/bin/activate" 2>/dev/null || true
    
    # Try to run with error handling
    if ! ansible-playbook \
        -i inventory/mycluster/hosts.ini \
        "$playbook_path" \
        -b --flush-cache \
        --become-user=root \
        --timeout=30; then
        echo "Error: Kubespray deployment failed"
        return 1
    fi
    
    echo ""
    echo "=================================="
    echo "Kubespray deployment completed successfully."
    echo "=================================="
}

function verify_deployment() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "Skipping verification in dry-run mode."
        echo "This would normally check cluster status and run validation tests."
        return
    fi
    
    echo "Verifying deployment results..."
    
    # Check if kubectl is available 
    if command -v kubectl &> /dev/null; then
        echo "kubectl found, checking cluster status..."
        
        # Get cluster nodes
        kubectl get nodes -o wide
        
        # Show system pods
        echo ""
        echo "Kubernetes system pods:"
        kubectl get pods -A | grep -E "(kube-|etcd-|cni-)" | head -10
        
    else 
        echo "kubectl not found, skipping verification"
    fi
}

function main() {
    parse_arguments "$@"
    
    echo "Starting Kubespray cluster deployment tool..."
    echo "=============================================="
    
    check_dependencies
    load_config
    validate_config
     
    # Show overview
    local master_count=${#MASTER_NODES[@]}
    local worker_count=${#WORKER_NODES[@]}
    echo "Configuration summary:"
    echo "  Masters: $master_count"
    echo "  Workers: $worker_count"
    echo "  Dry-run: $DRY_RUN"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "=== DRY RUN MODE ==="
        echo "Configuration is valid. Deploy would proceed with:"
        echo "  - Kubespray directory: $KUBESPRAY_DIR"
        echo "  - Master nodes: $master_count"
        echo "  - Worker nodes: $worker_count" 
        echo ""
    fi
    
    validate_ssh_connectivity
    generate_inventory
    validate_inventory

    if [[ "$DRY_RUN" == false ]]; then
        prepare_virtualenv
        deploy_cluster
        verify_deployment
    else
        echo "=== DRY RUN COMPLETE ==="
        echo "Deployment would proceed with generated inventory."
    fi
    
    echo "=================================="
    echo "Kubespray cluster deployment tool finished."
    echo "=================================="
}

# Run main function with all arguments
main "$@"
