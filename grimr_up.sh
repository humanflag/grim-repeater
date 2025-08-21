sudo tee /usr/local/bin/grimr_up.sh >/dev/null <<'EOF'
#!/bin/sh
set -eu

# Load SSID & PASSWORD
. /usr/local/etc/grim-repeater/config.env

NMCLI=/usr/bin/nmcli
AWK=/usr/bin/awk
CUT=/usr/bin/cut
GREP=/bin/grep
IW=/sbin/iw

IFACE_WLAN="wlan0"
IFACE_ETH="eth0"
CLIENT_CON="preconfigured"     # change if your client profile name differs
AP_CON="repeater-ap"           # AP profile

log(){ echo "[grimr] $*"; }

is_eth_up() {
  state="$($NMCLI -t -f GENERAL.STATE dev show "$IFACE_ETH" 2>/dev/null | $CUT -d: -f2 || true)"
  ip4="$($NMCLI -t -f IP4.ADDRESS dev show "$IFACE_ETH" 2>/dev/null | $CUT -d: -f2 || true)"
  [ "$state" = "100 (connected)" ] && [ -n "$ip4" ]
}

# Ensure AP has desired SSID/pass + shared IPv4
$NMCLI con modify "$AP_CON" \
  802-11-wireless.ssid "$SSID" \
  802-11-wireless-security.key-mgmt wpa-psk \
  802-11-wireless-security.psk "$PASSWORD" \
  ipv4.method shared ipv6.method ignore || true

# Decide band/channel:
BAND="bg"
CHAN=""

if is_eth_up; then
  log "Ethernet is up; using default/fixed AP channel if client channel unknown."
else
  # Try to ensure client is up
  ACTIVE_CON="$($NMCLI -t -f GENERAL.CONNECTION dev show "$IFACE_WLAN" 2>/dev/null | $CUT -d: -f2 || true)"
  if [ -z "$ACTIVE_CON" ] || [ "$ACTIVE_CON" = "--" ]; then
    $NMCLI con up "$CLIENT_CON" || log "WARN: could not bring client '$CLIENT_CON' up"
    sleep 2 || true
  fi

  # Try detect channel/ssid via nmcli, fallback to iw
  CHAN="$($NMCLI -t -f ACTIVE,CHAN dev wifi 2>/dev/null | $AWK -F: '$1=="yes"{print $2; exit}')"
  [ -z "${CHAN:-}" -o "$CHAN" = "--" ] && CHAN="$($IW dev "$IFACE_WLAN" link 2>/dev/null | $AWK '/channel/{print $2; exit}')"
fi

# If still no channel, fall back to 2.4 GHz ch6
if [ -z "${CHAN:-}" ]; then
  CHAN="6"
  BAND="bg"
else
  if [ "$CHAN" -gt 14 ] 2>/dev/null; then BAND="a"; else BAND="bg"; fi
fi

# Apply band/channel and start AP if not already active
$NMCLI con mod "$AP_CON" 802-11-wireless.band "$BAND" 802-11-wireless.channel "$CHAN" || true

if ! $NMCLI -t -f NAME,TYPE,DEVICE con show --active | $GREP -q "^$AP_CON:wifi:$IFACE_WLAN$"; then
  $NMCLI con up "$AP_CON"
fi

# Status line
SSID_CUR="$($NMCLI -t -f ACTIVE,SSID dev wifi 2>/dev/null | $AWK -F: '$1=="yes"{print $2; exit}')" || SSID_CUR=""
[ -z "${SSID_CUR:-}" ] && SSID_CUR="(eth0 upstream or unknown)"
log "AP '$SSID' up on ch$CHAN ($BAND). Upstream: $SSID_CUR"
EOF

sudo chmod +x /usr/local/bin/grimr_up.sh
