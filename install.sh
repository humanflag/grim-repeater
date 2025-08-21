#!/bin/bash
set -euo pipefail

REPO="https://raw.githubusercontent.com/YOURUSER/grim-repeater/main"

echo "🔧 Installing Grim Repeater…"

# --- sanity checks ---
command -v nmcli >/dev/null || { echo "Installing NetworkManager…"; sudo apt-get update && sudo apt-get install -y network-manager; }
command -v iw >/dev/null || { echo "Installing iw…"; sudo apt-get update && sudo apt-get install -y iw; }

# --- paths ---
CFG_DIR="/usr/local/etc/grim-repeater"
CFG_FILE="$CFG_DIR/config.env"
BIN="/usr/local/bin/repeater_up.sh"
UNIT="/etc/systemd/system/repeater.service"

# --- fetch files from repo ---
sudo mkdir -p "$CFG_DIR"
echo "⬇️  Downloading config/env + scripts from repo…"
sudo curl -fsSL "$REPO/config.env" -o "$CFG_FILE"
sudo curl -fsSL "$REPO/repeater_up.sh" -o "$BIN"
sudo curl -fsSL "$REPO/repeater.service" -o "$UNIT"

sudo chmod 600 "$CFG_FILE"
sudo chmod +x "$BIN"

# --- load config ---
set +u
. "$CFG_FILE"
set -u
SSID="${SSID:-Grim Repeater}"
PASSWORD="${PASSWORD:-12345687}"

# --- Wi-Fi stability tweaks (recommended) ---
sudo mkdir -p /etc/NetworkManager/conf.d
printf "[connection]\nwifi.powersave=2\n" | sudo tee /etc/NetworkManager/conf.d/10-wifi-powersave.conf >/dev/null
cat <<'EOF' | sudo tee /etc/NetworkManager/conf.d/20-mac.conf >/dev/null
[connection]
wifi.mac-address-randomization=0
[device]
wifi.scan-rand-mac-address=no
EOF
sudo systemctl reload NetworkManager || true

# --- make sure Wi-Fi radio is on ---
sudo nmcli radio wifi on || true

# --- ensure the AP connection exists (create if missing) ---
AP_NAME="repeater-ap"
IFACE="wlan0"

if ! nmcli -t -f NAME connection show | grep -qx "$AP_NAME"; then
  echo "Creating AP profile '$AP_NAME'…"
  sudo nmcli connection add \
    type wifi ifname "$IFACE" con-name "$AP_NAME" autoconnect no \
    802-11-wireless.mode ap \
    802-11-wireless.band bg \
    802-11-wireless.channel 6 \
    802-11-wireless.ssid "$SSID" \
    ipv4.method shared ipv6.method ignore \
    802-11-wireless-security.key-mgmt wpa-psk \
    802-11-wireless-security.psk "$PASSWORD"
else
  echo "AP profile '$AP_NAME' already exists — updating SSID/password…"
  sudo nmcli connection modify "$AP_NAME" \
    802-11-wireless.ssid "$SSID" \
    802-11-wireless-security.key-mgmt wpa-psk \
    802-11-wireless-security.psk "$PASSWORD" \
    ipv4.method shared ipv6.method ignore
fi

# Never autostart AP by itself
sudo nmcli connection modify "$AP_NAME" connection.autoconnect no || true

# --- enable + start service ---
sudo systemctl daemon-reload
sudo systemctl enable repeater.service
sudo systemctl restart repeater.service

echo "✅ Install complete."
echo "⚙️  Config: $CFG_FILE  (SSID=\"$SSID\", PASSWORD=\"$PASSWORD\")"
echo "🔁 Service: repeater.service (enabled & started)"
echo "ℹ️  Reboot recommended: sudo reboot"

# --- verification section ---
echo ""
echo "🔍 Active connections:"
nmcli con show --active || true

echo ""
echo "📡 AP config summary:"
nmcli connection show repeater-ap | egrep 'ssid|psk|mode|band|channel|ipv4.method' || true

echo ""
echo "📝 Service logs (last boot):"
journalctl -u repeater.service -b --no-pager -n 30 || true
