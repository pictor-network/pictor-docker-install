#!/bin/bash

sudo apt update
sudo apt install -y nvidia-driver-535

# Detect Ubuntu version ID (e.g., "20.04", "22.04", "24.04")
ubuntu_version=$(lsb_release -rs)

# Default to current system version
distribution="ubuntu${ubuntu_version}"

# If system is Ubuntu 24.04 (noble), fallback to ubuntu22.04 for NVIDIA compatibility
if [[ "$ubuntu_version" == "24.04" ]]; then
  echo "[INFO] Detected Ubuntu 24.04. Using ubuntu22.04 repo for NVIDIA container toolkit compatibility."
  distribution="ubuntu22.04"
else
  echo "[INFO] Detected Ubuntu $ubuntu_version. Using native repo for NVIDIA container toolkit."
fi

# Add NVIDIA container repo (based on adjusted $distribution)
curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit.gpg] https://#' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Install NVIDIA container toolkit
sudo apt update
sudo apt install -y nvidia-container-toolkit

# Configure Docker runtime
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

echo "[DONE] NVIDIA container toolkit installation completed. Please reboot the system."
