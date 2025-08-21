# Grim Repeater 🛰️

Turns a Raspberry Pi into a smart Wi-Fi and Ethernet repeater.

---

## Install

Quick install:

```bash
curl -fsSL https://raw.githubusercontent.com/humanflag/grim-repeater/main/install.sh | bash
Manual install:

bash
Copy
Edit
git clone https://github.com/humanflag/grim-repeater
cd grim-repeater
chmod +x install.sh
./install.sh
sudo reboot
Config
Edit the config file to change SSID or password:

bash
Copy
Edit
sudo nano /usr/local/etc/grim-repeater/config.env
Default values
ini
Copy
Edit
SSID="Grim Repeater"
PASSWORD="12345687"
Usage
After installation, use the grimr helper to control and inspect the repeater:

bash
Copy
Edit
grimr status     # show repeater + Wi-Fi status
grimr logs       # view recent service logs
grimr start      # start the service
grimr stop       # stop the service
grimr restart    # restart the service
grimr active     # list active connections
grimr ap         # show AP (access point) configuration
Uninstall
Remove Grim Repeater completely:

bash
Copy
Edit
grimr-uninstall
Notes
Works with Wi-Fi → Wi-Fi repeating.

Can also share Ethernet → Wi-Fi if wlan0 is used for AP and eth0 provides upstream.

Uses NetworkManager for stable connection handling.