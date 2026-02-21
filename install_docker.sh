#!/bin/bash

# Exit loosely on errors
set -e

echo "Starting Docker installation process..."

# Check if Docker is already installed
if command -v docker &> /dev/null; then
    echo "Docker is already installed. Checking version..."
    docker --version
else
    echo "Installing Docker using the official installation script..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
    echo "Docker installed successfully."
fi

# Add current user to the docker group so sudo is not needed
if id -nG "$USER" | grep -qw "docker"; then
    echo "User $USER is already in the docker group."
else
    echo "Adding user $USER to the docker group..."
    sudo usermod -aG docker "$USER"
    echo "IMPORTANT: You need to log out and log back in (or run 'newgrp docker') for the group changes to take effect."
fi

# Ensure docker service is running and enabled on boot
echo "Enabling and starting Docker service..."
sudo systemctl enable docker.service
sudo systemctl enable containerd.service
sudo systemctl start docker.service

echo "Docker installation and setup complete!"
echo "You can now run 'docker compose up -d' to start the proxy after configuring the passwords."
