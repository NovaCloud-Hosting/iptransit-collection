#!/bin/bash
set -euo pipefail

if ! command -v systemctl >/dev/null 2>&1; then
  echo "Error: systemd/systemctl is not installed." >&2
  exit 1
fi

echo "You can view this required information in the customer dashboard or obtain it from Support."

while [[ -z "${NETBIRD_SETUP_TOKEN:-}" ]]; do
  read -r -p "Netbird Setup-Token: " NETBIRD_SETUP_TOKEN < /dev/tty

  if [[ -z "$NETBIRD_SETUP_TOKEN" ]]; then
    echo "Error: Netbird Setup-Token is mandatory." >&2
  fi
done

cat << EOF > /etc/systemd/system/netbird-iptransit.service
[Unit]
Description=NetBird IP-Transit Service
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
Environment=NB_STATE_DIR=/run/netbird-iptransit/state
Environment=NB_CONFIG=/run/netbird-iptransit/default.json
Environment=NB_DAEMON_ADDR=unix:///run/netbird-iptransit/netbird.sock

ExecStartPre=install -d -m 0700 -o root -g root /run/netbird-iptransit
ExecStartPre=install -d -m 0700 -o root -g root /run/netbird-iptransit/state
ExecStart=netbird service run --log-file console --daemon-addr \${NB_DAEMON_ADDR}
ExecStartPost=netbird up --mtu 1420 --interface-name wt10 --management-url https://netbird.iptransit.cloud --setup-key '${NETBIRD_SETUP_TOKEN}' --disable-dns --disable-firewall
ExecStartPost=sh -c 'while true; do echo "1" > /proc/sys/net/ipv4/conf/wt10/forwarding 2>/dev/null || true; ip -4 rule flush table 7120 2>/dev/null || true; ip -6 rule flush table 7120 2>/dev/null || true; sleep 1; done &'
ExecStartPost=sh -c 'ip -4 route add default dev wt10 table 10 || ip -4 route change default dev wt10 table 10'
ExecStartPost=sh -c 'ip -6 route add default dev wt10 table 10 || ip -6 route change default dev wt10 table 10'
ExecStartPost=ip -4 rule add pref 11 fwmark 0x10/0x10 lookup 10
ExecStartPost=ip -6 rule add pref 11 fwmark 0x10/0x10 lookup 10
ExecStartPost=iptables -t mangle -A PREROUTING -i wt10 -m conntrack --ctstate NEW -j CONNMARK --set-xmark 0x10/0x10
ExecStartPost=ip6tables -t mangle -A PREROUTING -i wt10 -m conntrack --ctstate NEW -j CONNMARK --set-xmark 0x10/0x10
ExecStartPost=iptables -t mangle -A PREROUTING -m conntrack --ctstate ESTABLISHED,RELATED --ctdir REPLY -m connmark --mark 0x10/0x10 -j CONNMARK --restore-mark --nfmask 0x10 --ctmask 0x10
ExecStartPost=ip6tables -t mangle -A PREROUTING -m conntrack --ctstate ESTABLISHED,RELATED --ctdir REPLY -m connmark --mark 0x10/0x10 -j CONNMARK --restore-mark --nfmask 0x10 --ctmask 0x10
ExecStop=netbird deregister
ExecStopPost=rm -rf /run/netbird-iptransit
ExecStopPost=sh -c 'while ip -4 rule del pref 11 2>/dev/null; do :; done'
ExecStopPost=sh -c 'while ip -6 rule del pref 11 2>/dev/null; do :; done'
ExecStopPost=iptables -t mangle -D PREROUTING -i wt10 -m conntrack --ctstate NEW -j CONNMARK --set-xmark 0x10/0x10
ExecStopPost=ip6tables -t mangle -D PREROUTING -i wt10 -m conntrack --ctstate NEW -j CONNMARK --set-xmark 0x10/0x10
ExecStopPost=iptables -t mangle -D PREROUTING -m conntrack --ctstate ESTABLISHED,RELATED --ctdir REPLY -m connmark --mark 0x10/0x10 -j CONNMARK --restore-mark --nfmask 0x10 --ctmask 0x10
ExecStopPost=ip6tables -t mangle -D PREROUTING -m conntrack --ctstate ESTABLISHED,RELATED --ctdir REPLY -m connmark --mark 0x10/0x10 -j CONNMARK --restore-mark --nfmask 0x10 --ctmask 0x10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

cat << EOF
Systemd-Service netbird-iptransit.service Installed!

Please make sure iptables is installed, e.g. using:
apt install -y iptables

To start the service, use:
systemctl start netbird-iptransit.service

To start the service automatically at boot time, use:
systemctl enable netbird-iptransit.service
EOF