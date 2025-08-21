#!/bin/sh
set -eu

. /usr/local/etc/grim-repeater/config.env

NMCLI=/usr/bin/nmcli
IWLIST=/sbin/iwlist
AWK=/usr/bin/awk

IFACE_WLAN="wlan0"
IFACE_ETH="eth0"
AP_CON="repeater-ap"

log(){ echo "[grimr] $*"; }

# Default
BAND="bg"
CHAN="6"

# Ethernet uplink?
if $NMCLI dev status | grep -q "^$IFACE_ETH.*connected"; then
  log "Ethernet uplink detected, using default channel $CHAN"
else
  # Wi-Fi uplink?
  UPLINK_CHAN="$($NMCLI -t -f ACTIVE,CHAN dev wifi 2>/dev/null | $AWK -F: '$1=="yes"{print $2; exit}')"
  if [ -n "${UPLINK_CHAN:-}" ] && [ "$UPLINK_CHAN" != "--" ]; then
    CHAN="$UPLINK_CHAN"
    [ "$CHAN" -gt 14 ] 2>/dev/null && BAND="a" || BAND="bg"
    log "Following uplink Wi-Fi on channel $CHAN ($BAND)"
  else
    # No uplink — scan for least used channel
    log "No uplink, scanning for free channel…"
    # Count APs per channel (2.4 GHz only)
    USED="$($IWLIST $IFACE_WLAN scan 2>/dev/null | grep 'Channel:' | cut -d: -f2 | sort | uniq -c | sort -n)"
    log "Channel usage: $USED"
    # Default to 6, prefer 1/6/11 if clear
    for C in 1 6 11; do
      if ! echo "$USED" | grep -q " $C\$"; then
        CHAN="$C"
        break
      fi
    done
    log "Picked channel $CHAN ($BAND)"
  fi
fi

# Apply config
$NMCLI con mod "$AP_CON" \
  802-11-wireless.ssid "$SSID" \
  802-11-wireless.band "$BAND" \
  802-11-wireless.channel "$CHAN" \
  802-11-wireless-security.key-mgmt wpa-psk \
  802-11-wireless-security.psk "$PASSWORD" \
  ipv4.method shared ipv6.method ignore || true

$NMCLI con up "$AP_CON"

log "✅ AP '$SSID' running on ch$CHAN ($BAND)"
