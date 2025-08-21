#!/bin/sh
set -e

. /usr/local/etc/grim-repeater/config.env   # Load SSID & PASSWORD

NMCLI=/usr/bin/nmcli
AWK=/usr/bin/awk
CUT=/usr/bin/cut
GREP=/bin/grep
IW=/sbin/iw

IFACE="wlan0"
CLIENT_CON="preconfigured"   # change if your client profile has a different name
AP_CON="repeater-ap"         # your AP profile

# Ensure AP config matches chosen SSID + password
$NMCLI con modify "$AP_CON" \
  802-11-wireless.ssid "$SSID" \
  802-11-wireless-security.psk "$PASSWORD" \
  ipv4.method shared ipv6.method ignore

# Ensure client is up (or bring it up)
ACTIVE_CON=$($NMCLI -t -f GENERAL.CONNECTION dev show "$IFACE" 2>/dev/null | $CUT -d: -f2 || true)
if [ -z "$ACTIVE_CON" ] || [ "$ACTIVE_CON" = "--" ]; then
  $NMCLI con up "$CLIENT_CON" || {
    echo "ERROR: couldn't bring client '$CLIENT_CON' up"
    exit 1
  }
  sleep 2
fi

# Detect SSID and channel (nmcli first, then iw fallback)
SSID_CUR=$($NMCLI -t -f ACTIVE,SSID dev wifi 2>/dev/null | $AWK -F: '$1=="yes"{print $2; exit}')
CHAN=$($NMCLI -t -f ACTIVE,CHAN dev wifi 2>/dev/null | $AWK -F: '$1=="yes"{print $2; exit}')

if [ -z "$CHAN" ] || [ "$CHAN" = "--" ]; then
  SSID_CUR=$($IW dev "$IFACE" link 2>/dev/null | $AWK '/SSID/ { $1=""; sub(/^ /,""); print; exit }')
  CHAN=$($IW dev "$IFACE" link 2>/dev/null | $AWK '/channel/ {print $2; exit}')
fi

if [ -z "$CHAN" ]; then
  echo "ERROR: couldn't detect current Wi-Fi channel on $IFACE"
  exit 1
fi

BAND="bg"
[ "$CHAN" -gt 14 ] && BAND="a"

$NMCLI con mod "$AP_CON" 802-11-wireless.band "$BAND" 802-11-wireless.channel "$CHAN"

if ! $NMCLI -t -f NAME,TYPE,DEVICE con show --active | $GREP -q "^$AP_CON:wifi:$IFACE$"; then
  $NMCLI con up "$AP_CON" || true
fi

echo "✅ Client '$ACTIVE_CON' on SSID '$SSID_CUR' ch$CHAN ($BAND); AP '$SSID' started with password '$PASSWORD'."
