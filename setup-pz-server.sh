#!/usr/bin/env bash
# Project Zomboid Build 42 dedicated server bootstrap for Ubuntu (Oracle Cloud Always Free).
# Run this ON THE VM as the sudo-capable user (e.g. `ubuntu`), not on your local machine.
#   chmod +x setup-pz-server.sh
#   ./setup-pz-server.sh [servername]

set -euo pipefail

SERVERNAME="${1:-myserver}"
INSTALL_DIR="$HOME/pzserver"
CONFIG="$HOME/Zomboid/Server/${SERVERNAME}.ini"

echo "== Firewall (OS level) =="
sudo apt-get update -y
sudo apt-get install -y ufw software-properties-common
sudo ufw allow OpenSSH
sudo ufw allow 16261/udp
sudo ufw allow 16262/udp
sudo ufw --force enable

echo "== SteamCMD =="
# Pre-accept the Steam license so the install doesn't hang on a prompt.
echo steam steam/question select "I AGREE" | sudo debconf-set-selections
echo steam steam/license note '' | sudo debconf-set-selections
sudo add-apt-repository -y multiverse
sudo dpkg --add-architecture i386
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y steamcmd lib32gcc-s1

echo "== Downloading Project Zomboid dedicated server (B42 is the default branch, no -beta needed) =="
steamcmd +force_install_dir "$INSTALL_DIR" +login anonymous +app_update 380870 validate +quit

echo "== First run to generate config files =="
cd "$INSTALL_DIR"
chmod +x start-server.sh
timeout --signal=SIGTERM 90 ./start-server.sh -servername "$SERVERNAME" || true

if [ -f "$CONFIG" ]; then
  RCON_PASS=$(openssl rand -hex 12)
  sed -i "s/^Public=.*/Public=true/" "$CONFIG"
  sed -i "s/^RCONPort=.*/RCONPort=27015/" "$CONFIG"
  sed -i "s/^RCONPassword=.*/RCONPassword=${RCON_PASS}/" "$CONFIG"
  echo ">>> RCON password set to: ${RCON_PASS}  (save this — it won't be shown again)"
else
  echo "!! Config not found at $CONFIG yet — first boot may need more time on a slow VM."
  echo "!! Re-run: cd $INSTALL_DIR && ./start-server.sh -servername $SERVERNAME   then Ctrl+C once it says 'Server listening'."
fi

echo "== systemd service so it survives reboot/logout =="
sudo tee /etc/systemd/system/pzserver.service > /dev/null <<EOF
[Unit]
Description=Project Zomboid Dedicated Server
After=network.target

[Service]
Type=simple
User=${USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/start-server.sh -servername ${SERVERNAME}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now pzserver

echo "== Done =="
echo "Check status:   sudo systemctl status pzserver"
echo "Live logs:      journalctl -u pzserver -f"
echo "Connect:        <this-VM-public-IP>:16261"
echo "IMPORTANT: also open UDP 16261/16262 in the Oracle VCN Security List (cloud-level firewall) — this script only opened the OS-level one."
