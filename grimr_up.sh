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
CLIENT_CON="preconfigured"     # change if your client profile differs
AP_CON="repeater-ap"           # AP profile

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

ensure_client_up() {
  if ! client_active; then
    $NMCLI con up "$CLIENT_CON" >/dev/null 2>&1 || true
    sleep 2
  fi
}

# Bring AP down if it's currently active
ap_down_if_up() {
  if $NMCLI -t -f NAME,TYPE,DEVICE con show --active | $GREP -q "^$AP_CON:wifi:$IFACE_WLAN$"; then
    log "Bringing AP down to free radio for scanning…"
    $NMCLI con down "$AP_CON" || true
    # give wpa_supplicant a moment to release the interface
    sleep 1
  fi
}

# Rescan & return least-used channel among 1/6/11
pick_2g_least_used() {
  $NMCLI dev wifi rescan >/dev/null 2>&1 || true
  # brief wait so scan results populate
  sleep 1
  list="$($NMCLI -f IN-USE,SSID,CHAN dev wifi 2>/dev/null | tail -n +2 || true)"
  c1=$(printf "%s\n" "$list" | $AWK '$3==1  && $2!=""{c++} END{print c+0}')
  c6=$(printf "%s\n" "$list" | $AWK '$3==6  && $2!=""{c++} END{print c+0}')
  c11=$(printf "%s\n" "$list" | $AWK '$3==11 && $2!=""{c++} END{print c+0}')
  best=1; min=$c1
  [ "$c6"  -lt "$min" ] && best=6  && min=$c6
  [ "$c11" -lt "$min" ] && best=11 && min=$c11
  echo "$best"
}

# Ensure AP has desired SSID/password & shared IPv4
$NMCLI con modify "$AP_CON" \
  802-11-wireless.ssid "$SSID" \
  802-11-wireless-security.key-mgmt wpa-psk \
  802-11-wireless-security.psk "$PASSWORD" \
  ipv4.method shared ipv6.method ignore || true

BAND="bg"
CHAN=""

# --- DECISION TREE ---

# 1) Prefer matching Wi-Fi client if active
ensure_client_up
if client_active; then
  CHAN="$($NMCLI -t -f ACTIVE,CHAN dev wifi 2>/dev/null | $AWK -F: '$1=="yes"{print $2; exit}')"
  [ -z "${CHAN:-}" -o "$CHAN" = "--" ] && CHAN="$($IW dev "$IFACE_WLAN" link 2>/dev/null | $AWK '/channel/{print $2; exit}')"
  if [ -n "${CHAN:-}" ]; then
    [ "$CHAN" -gt 14 ] 2>/dev/null && BAND="a" || BAND="bg"
    log "Wi-Fi uplink detected; matching channel $CHAN ($BAND)."
  fi
fi

# 2) If no Wi-Fi client channel, but Ethernet up → down AP, scan, pick least-used 1/6/11
if [ -z "${CHAN:-}" ] && is_eth_up; then
  ap_down_if_up
  CHAN="$(pick_2g_least_used || true)"
  if [ -z "${CHAN:-}" ]; then
    CHAN="6"
    log "Scan returned nothing; falling back to ch6."
  else
    log "Ethernet uplink; picked least-used 2.4 GHz channel $CHAN."
  fi
  BAND="bg"
fi

# 3) If still nothing (no uplink), also down AP, scan, pick least-used 1/6/11
if [ -z "${CHAN:-}" ]; then
  ap_down_if_up
  CHAN="$(pick_2g_least_used || true)"
  if [ -z "${CHAN:-}" ]; then
    CHAN="6"
    log "No uplink and scan empty; falling back to ch6."
  else
    log "No uplink; picked least-used 2.4 GHz channel $CHAN."
  fi
  BAND="bg"
fi

# Force re-apply AP profile cleanly
$NMCLI con down "$AP_CON" >/dev/null 2>&1 || true
sleep 1
$NMCLI con mod "$AP_CON" \
  802-11-wireless.band "$BAND" \
  802-11-wireless.channel "$CHAN"
sleep 1
$NMCLI con up "$AP_CON" >/dev/null || true



SSID_CUR="$($NMCLI -t -f ACTIVE,SSID dev wifi 2>/dev/null | $AWK -F: '$1=="yes"{print $2; exit}')" || SSID_CUR=""
[ -z "${SSID_CUR:-}" ] && SSID_CUR="(eth0 or none)"
log "✅ AP '$SSID' running on ch$CHAN ($BAND); upstream: $SSID_CUR"
