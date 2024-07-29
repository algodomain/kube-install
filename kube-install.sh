#!/bin/bash

# Check if the node is master
read -p "Is this a master node? (yes/no): " is_master

if [ "$is_master" == "yes" ]; then
  # Step 1: Install Nginx and Keepalived
  echo "Installing Nginx and Keepalived..."
  sudo apt-get update
  sudo apt-get install -y nginx keepalived

  # Step 2: Create Keepalived Configuration
  # Ask for Virtual IP (VIP)
  read -p "Enter the Virtual IP (VIP) address to be used: " VIP

  # Ask for Network Interface
  read -p "Enter the network interface to be used by Keepalived (e.g., ens18): " INTERFACE

  read -p "Is this the root control plane? (yes/no): " is_root
  if [ "$is_root" == "yes" ]; then
    PRIORITY=100
    TYPE="MASTER"
  else
    read -p "Enter the number of this control plane node: " cp_number
    PRIORITY=$((100 - cp_number))
    TYPE="BACKUP"
  fi

  # Generate Keepalived configuration
  cat <<EOF | sudo tee /etc/keepalived/keepalived.conf
vrrp_instance VI_1 {
    state $TYPE
    interface $INTERFACE
    virtual_router_id 51
    priority $PRIORITY
    advert_int 1
    virtual_ipaddress {
        $VIP
    }
}
EOF
  sudo systemctl restart keepalived
  echo "Keepalived configuration is complete!"
else
  echo "This is not a master node. Skipping Keepalived and Nginx installation."
fi

# Step 3: Install Containerd and Kubernetes Cluster
echo "Installing Containerd and Kubernetes Cluster..."

# Update package list and install dependencies
sudo apt-get update
sudo apt-get install -y ca-certificates curl apt-transport-https jq

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package list and install Docker
sudo apt-get update
sudo apt-get install -y containerd.io

sudo containerd config default > /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd >/dev/null

sudo sysctl -w net.ipv4.ip_forward=1
sudo sh -c 'echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf'

# Add Kubernetes GPG key and repository
sudo mkdir -p /etc/apt/keyrings
sudo apt-get install -y gnupg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update package list and install Kubernetes packages
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Permanently disable swap
sudo swapoff -a
sudo sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Start containerd and kubelet
sudo systemctl start containerd
sudo systemctl enable containerd
sudo systemctl start kubelet
sudo systemctl enable kubelet

# Check if the node is master and run kubeadm commands
if [ "$is_master" == "yes" ]; then
  if [ "$is_root" == "yes" ]; then
    sudo kubeadm init --control-plane-endpoint "$VIP:6443" --pod-network-cidr=10.244.0.0/16 --upload-certs
  else
    read -p "Enter the join token: " TOKEN
    read -p "Enter the discovery-token-ca-cert-hash: " CA_CERT_HASH
    read -p "Enter the certificate key: " CERTIFICATE_KEY
    sudo kubeadm join "$VIP:6443" --token "$TOKEN" --discovery-token-ca-cert-hash "sha256:$CA_CERT_HASH" --control-plane --certificate-key "$CERTIFICATE_KEY"
  fi
else
  # If the node is not master, join as a worker node
  read -p "Enter the join token: " TOKEN
  read -p "Enter the discovery-token-ca-cert-hash: " CA_CERT_HASH
  sudo kubeadm join "$VIP:6443" --token "$TOKEN" --discovery-token-ca-cert-hash "sha256:$CA_CERT_HASH"
fi

echo "Setup is complete!"
