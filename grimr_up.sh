#!/bin/sh
set -eu

. /usr/local/etc/grim-repeater/config.env

NMCLI=/usr/bin/nmcli
AWK=/usr/bin/awk
CUT=/usr/bin/cut
GREP=/bin/grep
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

ensure_client_up() {
  if ! client_active; then
    $NMCLI con up "$CLIENT_CON" >/dev/null 2>&1 || true
    sleep 2
  fi
}

pick_2g_least_used() {
  $NMCLI dev wifi rescan >/dev/null 2>&1 || true
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

  # If AP active but on wrong channel, bounce just the AP
  CUR_CH="$($NMCLI -g 802-11-wireless.channel connection show "$AP_CON" 2>/dev/null || echo "")"
  if [ "$CUR_CH" != "$CHAN" ]; then
    $NMCLI con down "$AP_CON" >/dev/null 2>&1 || true
  fi

  if ! $NMCLI -t -f NAME,TYPE,DEVICE con show --active | $GREP -q "^$AP_CON:wifi:$IFACE_WLAN$"; then
    if ! $NMCLI con up "$AP_CON" >/dev/null 2>&1; then
      sleep 1
      $NMCLI con up "$AP_CON" >/dev/null 2>&1 || true
    fi
  fi
}

# --- decision tree ---

ensure_client_up

if client_active; then
  # STRICT matching to STA channel; never scan here.
  CHAN="$($NMCLI -t -f ACTIVE,CHAN dev wifi 2>/dev/null | $AWK -F: '$1=="yes"{print $2; exit}')"
  [ -z "${CHAN:-}" -o "$CHAN" = "--" ] && CHAN="$($IW dev "$IFACE_WLAN" link 2>/dev/null | $AWK '/channel/{print $2; exit}')"

  if [ -n "${CHAN:-}" ]; then
    BAND="bg"; [ "$CHAN" -gt 14 ] 2>/dev/null && BAND="a"
    log "Wi-Fi uplink detected on ch$CHAN ($BAND); locking AP to the same channel."
    apply_ap "$BAND" "$CHAN"
    SSID_CUR="$($NMCLI -t -f ACTIVE,SSID dev wifi 2>/dev/null | $AWK -F: '$1=="yes"{print $2; exit}')" || SSID_CUR=""
    [ -z "${SSID_CUR:-}" ] && SSID_CUR="unknown"
    log "✅ AP '$SSID' running on ch$CHAN ($BAND); upstream: $SSID_CUR"
    exit 0
  else
    log "WARN: client active but channel unknown."
  fi
fi

if is_eth_up; then
  $NMCLI con down "$AP_CON" >/dev/null 2>&1 || true
  CHAN="$(pick_2g_least_used || echo 6)"
  log "Ethernet uplink; picked least-used 2.4 GHz channel $CHAN."
  apply_ap "bg" "$CHAN"
  log "✅ AP '$SSID' running on ch$CHAN (bg); upstream: eth0"
  exit 0
fi

# No uplink known; standalone AP on a lightly used 2.4 GHz channel
$NMCLI con down "$AP_CON" >/dev/null 2>&1 || true
CHAN="$(pick_2g_least_used || echo 6)"
log "No uplink; standalone AP on least-used 2.4 GHz channel $CHAN."
apply_ap "bg" "$CHAN"
log "✅ AP '$SSID' running on ch$CHAN (bg); upstream: none"