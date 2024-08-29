#!/bin/bash 

set -eu

#Reset
NC='\033[0m'       # Text Reset

# Regular Colors
export BLACK='\033[0;30m'        # Black
export RED='\033[0;31m'          # Red
export GREEN='\033[0;32m'        # Green
export YELLOW='\033[0;33m'       # Yellow
export BLUE='\033[0;34m'         # Blue
export PURPLE='\033[0;35m'       # Purple
export CYAN='\033[0;36m'         # Cyan
export WHITE='\033[0;37m'        # White

# Function to load .env file
load_env() {
    if [ -f .env ]; then
    # Read each line in .env file
    while IFS='=' read -r key value
    do
        # Ignore comments and empty lines
        if [[ $key != \#* ]] && [ -n "$key" ]; then
            # Remove any leading/trailing whitespace
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            
            # Export the variable
            export "$key"="${value}"
            echo  -e "${YELLOW}Exported ${BLUE}$key${NC}"
        fi
    done < .env
    echo "Environment variables loaded."
    else
    echo ".env file not found."
    fi
}

run_on_remote() { 
  local command=${1}

  ssh_command="export VM_ID=${VM_ID}; export VM_NAME=${VM_NAME}; export VM_MEMORY=${VM_MEMORY}; export VM_CORES=${VM_CORES}; ${command}" 
  echo "$ssh_command"
  sshpass -p "${PROXMOX_PASS}" ssh -o StrictHostKeyChecking=no  "${PROXMOX_USERNAME}"@"${PROXMOX_IP}" "${ssh_command}" 
}



## Cheak it see if the command exist
command_exist() { 
  if command -v "${1}" &>/dev/null; then 
    echo -e "${YELLOW}${1}${NC} command exist" 
  else
    echo -e "${RED}{1}${NC} doesn't exist installing now"
    apt install "${1}"
  fi 
}

change_hostname() { 
  hostname "${1}"
}

install_key_components() { 
  # Key commponents 
  #  - Kubeadm, kubectl, kubelet
  apt update
  apt-get install qemu-guest-agent
  ## Remember to reboot the system at the end
  systemctl start qemu-guest-agent

  # Installing kubectl, kubeadm, and kubelet 
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/kubernetes-archive-keyring.gpg add -
  echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
  apt-get update 
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
  chmod 644 /etc/apt/sources.list.d/kubernetes.list
  apt-get update 
  apt install kubectl kubeadm kubelet 


  # Installing containerd
  echo -e "Installing ${PURPLE}containerd${NC}...." 
  apt install containerd
  mkdir /etc/containerd 
  containerd config default | sudo tee /etc/containerd/config.toml
  echo -e "Installation Successful for ${GREEN}containerd${NC}...." 

  # installing helm
  echo -e "Installing ${PURPLE}Helm${NC}...."  
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 get_helm.sh
  ./get_heecho -e "Installation Successful for ${GREEN}Helm${NC}...." lm.sh
  echo -e "Installation Successful for ${GREEN}Helm${NC}...." 

  # Installing Flux
  echo -e "Installing ${PURPLE}Flux${NC}...."  
  curl -s https://fluxcd.io/install.sh | bash
  echo -e "Installation Successful for ${GREEN}Flux${NC}...." 

  
  # sudo vim /etc/fstab
  # sudo vim /etc/sysctl.conf
  # sudo vim /etc/modules-load.d/k8s.conf

}

initate_controller() { 
  # Find the ip address of the machine first
  ip_address=$(ip route get 1 | awk '{print $7; exit}')
  kubeadm init --control-plane-endpoint="${ip_address}" --node-name controller --pod-network-cidr=10.244.0.0/16
}

nfs_setup() { 

  echo "Setting up nfs..."

  echo "Setting up external-provisioner" 

  git clone https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner.git
  pushd nfs-subdir-external-provisioner/
  popd
  kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/nfs-subdir-external-provisioner/master/deploy/crd.yaml
  helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
  helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner     --set nfs.server=10.0.4.26     --set nfs.path=/mnt/pve/storage
  
  kubectl patch storageclass nfs-storage-class -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
  kubectl patch storageclass nfs-client -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
}

create_vm() { 

  run_on_remote "qm create $VM_ID --name $VM_NAME --memory $VM_MEMORY --cores $VM_CORES --net0 virtio,bridge=vmbr0"
}

main() {
  
  # Load environment variables
  load_env

  create_vm
  # install_key_components
  # change_hostname controller
  #Create nodes 
  #     Maybe use proxmox api
  # nfs_setup
}

## Run main functinon 
main
