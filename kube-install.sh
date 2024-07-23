#!/bin/bash

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
sudo apt-get install -y docker-ce

# Install cri-dockerd
LATEST_VERSION=$(wget -qO- https://api.github.com/repos/Mirantis/cri-dockerd/releases/latest | jq -r '.tag_name')
echo "The latest version is: $LATEST_VERSION"

wget https://github.com/Mirantis/cri-dockerd/releases/download/$LATEST_VERSION/cri-dockerd-${LATEST_VERSION:1}.amd64.tgz
tar -xzf cri-dockerd-${LATEST_VERSION:1}.amd64.tgz
sudo mv cri-dockerd/cri-dockerd /usr/local/bin/
sudo chmod +x /usr/local/bin/cri-dockerd

# Create a systemd service file for cri-dockerd
cat <<EOF | sudo tee /etc/systemd/system/cri-dockerd.service > /dev/null
[Unit]
Description=CRI Docker Daemon
Documentation=https://github.com/Mirantis/cri-dockerd
Wants=docker.socket
After=docker.socket

[Service]
ExecStart=/usr/local/bin/cri-dockerd
Restart=always
RestartSec=10s
TimeoutSec=5min

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable the cri-dockerd service
sudo systemctl daemon-reload
sudo systemctl enable cri-dockerd

# Add Kubernetes GPG key and repository
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update package list and install Kubernetes packages
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Permanently disable swap
sudo swapoff -a
sudo sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Create kubeadm-config.yaml file
cat <<EOF | sudo tee /etc/kubeadm-config.yaml > /dev/null
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  criSocket: unix:///var/run/cri-dockerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
networking:
  podSubnet: 10.244.0.0/16
EOF

echo "Setup is complete!"
