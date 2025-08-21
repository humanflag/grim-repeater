#!/bin/bash
set -e

echo "🔧 Installing Grim Repeater..."

# Install needed tools
sudo apt-get update
sudo apt-get install -y network-manager wireless-tools iw

# Copy scripts
sudo mkdir -p /usr/local/bin
sudo cp repeater_up.sh /usr/local/bin/repeater_up.sh
sudo chmod +x /usr/local/bin/repeater_up.sh

# Copy service
sudo cp repeater.service /etc/systemd/system/repeater.service

# Reload systemd + enable service
sudo systemctl daemon-reload
sudo systemctl enable repeater.service

echo "✅ Grim Repeater installed."
echo "Reboot to activate: sudo reboot"
