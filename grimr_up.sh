#!/bin/sh
set -eu

. /usr/local/etc/grim-repeater/config.env

NMCLI=/usr/bin/nmcli
AWK=/usr/bin/awk
CUT=/usr/bin/cut
IW=/sbin/iw

IFACE_WLAN="wlan0"
IFACE_ETH="eth0"
CLIENT_CON="preconfigured"
AP_CON="repeater-ap"

log(){ echo "[grimr] $*"; }

is_eth_up() {
  state="$($NMCLI -t -f GENERAL.STATE dev show "$IFACE_ETH" 2>/dev/null | $CUT -d: -f2 || true)"
  ip4="$($NMCLI -t -f IP4.ADDRESS dev show "$IFACE_ETH" 2>/dev/null | $CUT -d: -f2 || true)"
  [ "$state" = "100 (connected)" ] && [ -n "$ip4" ]
}

client_active() {
  con="$($NMCLI -t -f GENERAL.CONNECTION dev show "$IFACE_WLAN" 2>/dev/null | $CUT -d: -f2 || true)"
  [ -n "$con" ] && [ "$con" != "--" ]
}

apply_ap() {
  BAND="$1"
  CHAN="$2"
  $NMCLI con mod "$AP_CON" \
    802-11-wireless.ssid "$SSID" \
    802-11-wireless-security.key-mgmt wpa-psk \
    802-11-wireless-security.psk "$PASSWORD" \
    802-11-wireless.band "$BAND" \
    802-11-wireless.channel "$CHAN" \
    ipv4.method shared ipv6.method ignore || true

  $NMCLI con down "$AP_CON" >/dev/null 2>&1 || true
  $NMCLI con up "$AP_CON" >/dev/null 2>&1 || true
}

# --- decision tree ---

if is_eth_up; then
  # Wired uplink → pure broadcaster mode
  log "Ethernet uplink detected; running AP only (no Wi-Fi client)."
  apply_ap "bg" 6
  log "✅ AP '$SSID' running on ch6 (bg); upstream: eth0"
  exit 0
fi

# Otherwise → Wi-Fi repeater mode
$NMCLI con up "$CLIENT_CON" >/dev/null 2>&1 || true
sleep 2

CHAN="$($NMCLI -t -f ACTIVE,CHAN dev wifi 2>/dev/null | $AWK -F: '$1=="yes"{print $2; exit}')"
[ -z "${CHAN:-}" -o "$CHAN" = "--" ] && \
  CHAN="$($IW dev "$IFACE_WLAN" link 2>/dev/null | $AWK '/channel/{print $2; exit}')"

if [ -n "${CHAN:-}" ]; then
  BAND="bg"; [ "$CHAN" -gt 14 ] 2>/dev/null && BAND="a"
  log "Wi-Fi uplink detected on ch$CHAN ($BAND); repeating on same channel."
  apply_ap "$BAND" "$CHAN"
  log "✅ AP '$SSID' running on ch$CHAN ($BAND); upstream: Wi-Fi"
  exit 0
else
  log "❌ No uplink found; AP not started."
  exit 1
fi
