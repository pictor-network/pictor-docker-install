#!/bin/bash

set -e

echo "🚀 Pictor Worker Installer (GPU-enabled)"
echo "🔎 Checking system prerequisites..."


# ────────────── Detect GPU type and install driver (NVIDIA or AMD) ──────────────
echo "🎯 Detecting GPU type..."

GPU_VENDOR=$(lspci | grep -i -E "nvidia|amd|advanced micro devices" | awk '{print tolower($0)}')
GPU_TYPE=""

if echo "$GPU_VENDOR" | grep -q "nvidia"; then
  echo "✅ NVIDIA GPU detected."
  GPU_TYPE="nvidia"
  IMAGE_REPO="pictornetwork/worker-app"
elif echo "$GPU_VENDOR" | grep -q "amd"; then
  echo "✅ AMD GPU detected."
  GPU_TYPE="amd"
  IMAGE_REPO="pictornetwork/worker-app-amd"
else
  echo "❌ No supported GPU detected (NVIDIA or AMD)."
  exit 1
fi

if (GPU_TYPE=="nvidia"); then
  if ! command -v nvidia-smi &> /dev/null; then
    echo "⚠️ nvidia-smi not found. NVIDIA driver or toolkit may be missing."
    echo "🔧 Suggest installing with: sudo apt install -y nvidia-driver-535 (or matching version)"
    echo "🔧 Or download URL and run it: install-gpu-driver-nvidia.sh"
    exit 1
  else
    echo "✅ NVIDIA driver is installed: $(nvidia-smi --query-gpu=name --format=csv,noheader)"
  fi

elif ((GPU_TYPE=="amd")); then
  if ! command -v rocminfo &> /dev/null; then
    echo "⚠️ rocminfo not found. ROCm may not be installed or configured yet."
    echo "🔧 Download URL and run it: install-gpu-driver-amd.sh"
    exit 1
  else
    echo "✅ ROCm is already installed: $(rocminfo | grep -i agent | head -n 1)"
  fi
fi

echo "✅ GPU driver is available."


# ────────────── Detect Docker ──────────────
# Check Docker binary
if ! command -v docker &> /dev/null; then
  echo "❌ Docker is not installed."
  echo "    === Updating system packages ==="
  sudo apt update

  echo "    === Installing required packages ==="
  sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

  echo "    === Adding Docker GPG key ==="
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

  echo "    === Setting up Docker repository ==="
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  echo "    === Updating package index again ==="
  sudo apt update

  echo "    === Installing Docker packages ==="
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  #sudo usermod -aG docker $USER

  echo "    === Docker installation completed ==="
  docker --version
fi

# Check Docker daemon
if ! sudo docker info &> /dev/null; then
  echo "❌ Docker is installed but not running. Starting the Docker service"
  sudo systemctl start docker
fi

# Check Docker version
docker_version=$(sudo docker version --format '{{.Server.Version}}')
major=$(echo "$docker_version" | cut -d'.' -f1)
minor=$(echo "$docker_version" | cut -d'.' -f2)

if (( major < 20 )); then
  echo "❌ Docker version is too old: $docker_version. Please upgrade to at least v20.x."
  exit 1
elif (( major == 24 && minor > 10 )); then
  echo "❌ Docker version $docker_version is more than 10 minor versions ahead. Please use a stable version."
  exit 1
fi

echo "✅ Docker version is acceptable: $docker_version"


# ────────────── Pull Image ──────────────
# Get latest image version from API
echo "🌐 Fetching latest image version from Pictor API..."
# LATEST_TAG=$(curl -s https://pictor.network/api/docker/version | jq -r '.version')
LATEST_TAG="v1.0"

if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" == "null" ]; then
  echo "❌ Failed to retrieve image version from API."
  exit 1
fi

IMAGE_NAME="${IMAGE_REPO}:${LATEST_TAG}"
echo "✅ Latest image tag is: $LATEST_TAG"

# Check if image already exists locally
if ! sudo docker image inspect "$IMAGE_NAME" &>/dev/null; then
  echo "⬇️ Image not found locally. Pulling $IMAGE_NAME..."
  sudo docker pull "$IMAGE_NAME"
else
  echo "✅ Image already exists locally: $IMAGE_NAME"

  # Check age of the local image
  image_created=$(sudo docker image inspect "$IMAGE_NAME" --format='{{.Created}}')
  image_age_days=$(( ( $(date +%s) - $(date -d "$image_created" +%s) ) / 86400 ))

  if (( image_age_days > 30 )); then
    echo "⚠️ Local image is over 30 days old ($image_age_days days). Consider pulling again:"
    echo "👉 docker pull $IMAGE_NAME"
  else
    echo "✅ Local image is recent: $image_age_days days old."
  fi
fi

DEFAULT_CONFIG_PATH="/home/ubuntu/worker-config.json"

# Ask for worker config
read -p "📄 Enter full path to your worker-config.json file (default is $DEFAULT_CONFIG_PATH): " CONFIG_PATH

if [ -z "$CONFIG_PATH" ]; then
  CONFIG_PATH="$DEFAULT_CONFIG_PATH"
fi

if [ ! -f "$CONFIG_PATH" ]; then
  echo "❌ File not found: $CONFIG_PATH"
  exit 1
fi


# ────────────── Handle existing container ──────────────
container_name="pictor-worker"
if sudo docker ps -a --format '{{.Names}}' | grep -qw "$container_name"; then
  container_status=$(sudo docker inspect -f '{{.State.Status}}' "$container_name")

  if [ "$container_status" == "running" ]; then
    echo "⚠️ Container '$container_name' is already running. Reusing it."
    echo "🛑 To stop container:  docker stop $container_name"
    exit 0
  elif [ "$container_status" == "exited" ] || [ "$container_status" == "created" ]; then
    echo "♻️ Removing stopped container '$container_name'..."
    sudo docker rm "$container_name"
  else
    echo "⚠️ Found container '$container_name' in unexpected state: $container_status"
    echo "❌ Please check manually."
    exit 1
  fi
else
  echo "✅ No existing container named '$container_name'."
fi


# ────────────── Run container with log mount ──────────────
echo "🚀 Starting Pictor Worker container as '$container_name'..."

if ((GPU_TYPE=="nvidia")); then
  sudo docker run -d --network host -e GPU_TYPE="$GPU_TYPE" --gpus all \
    --name "$container_name" \
    -v "$CONFIG_PATH":/worker-config.json \
    "$IMAGE_NAME" > /dev/null

elif ((GPU_TYPE=="amd")); then
  sudo docker run -d --network host -e GPU_TYPE="$GPU_TYPE" \
    --device=/dev/kfd \
    --device=/dev/dri \
    --group-add video \
    --name "$container_name" \
    -v "$CONFIG_PATH":/worker-config.json \
    "$IMAGE_NAME" > /dev/null
fi

echo "✅ Worker is running!"
echo "📌 Container Name: $container_name"
# echo "📦 View logs: docker logs -f $container_name"
echo "🛑 Stop:      docker stop $container_name"