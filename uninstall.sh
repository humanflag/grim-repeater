#!/bin/bash
set -e

echo "🧹 Uninstalling Grim Repeater..."

# Disable and remove service
sudo systemctl disable grimr.service || true
sudo rm -f /etc/systemd/system/grimr.service

# Remove script + config
sudo rm -f /usr/local/bin/grimr_up.sh
sudo rm -f /usr/local/bin/grimr
sudo rm -rf /usr/local/etc/grim-repeater

# Remove optimizations
sudo rm -f /etc/NetworkManager/conf.d/10-wifi-powersave.conf
sudo rm -f /etc/NetworkManager/conf.d/20-mac.conf
sudo systemctl reload NetworkManager

echo "✅ Grim Repeater removed. Reboot recommended."
