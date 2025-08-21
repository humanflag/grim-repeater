# Grim Repeater 🛰️

Turns a Raspberry Pi into a smart Wi-Fi repeater.

## Install
```
curl -fsSL https://raw.githubusercontent.com/humanflag/grim-repeater/main/install.sh | bash
```
or

```
git clone https://github.com/humanflag/grim-repeater 
cd grim-repeater 
chmod +x install.sh 
./install.sh 
sudo reboot
```

## Config
 edit /usr/local/etc/grim-repeater/config.env to set your SSID and PASSWORD

### Default:
SSID="Grim Repeater"
PASSWORD="12345687"

## Uninstall
./uninstall.sh
