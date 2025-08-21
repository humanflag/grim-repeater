#!/bin/bash
set -e

echo "🧹 Uninstalling Grim Repeater..."

# Disable and remove service
sudo systemctl disable repeater.service || true
sudo rm -f /etc/systemd/system/repeater.service

# Remove script + config
sudo rm -f /usr/local/bin/repeater_up.sh
sudo rm -rf /usr/local/etc/grim-repeater

# Remove optimizations
sudo rm -f /etc/NetworkManager/conf.d/10-wifi-powersave.conf
sudo rm -f /etc/NetworkManager/conf.d/20-mac.conf
sudo systemctl reload NetworkManager

echo "✅ Grim Repeater removed. Reboot recommended."
