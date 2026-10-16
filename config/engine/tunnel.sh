#!/bin/dash
# tunnel.sh - THE PHONE TUNNEL (WireGuard).
#
# WHY : the widget talks to a PRIVATE address of the desktop. On the same network, everything
# works ; on 4G, there is no path. This script raises the only path that exists without opening
# the bridge to the Internet : a WireGuard tunnel between the phone and the desktop.
#
# WHAT IT SETS, AND NOTHING MORE :
#   - the wg0 interface on the desktop, address 10.10.0.1/24, listen port 51820/UDP ;
#   - a single peer : the phone, 10.10.0.2/32 ;
#   - NO routing, NO NAT, NO traffic redirection : the phone only REACHES the desktop.
#     AllowedIPs is bounded to 10.10.0.0/24 on both sides : the phone's browsing does not go
#     through here.
#
# WHAT IT CANNOT DO : open the port on the box. The UDP redirect 51820 to 192.168.8.2 remains a
# gesture of MOUSSA's hand.
#
# THE PRIVATE KEYS NEVER LEAVE : they go into files, never to the output.
set -e
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
W="$ROOT/work"
CONF=/etc/wireguard/wg0.conf
PORT=51820
PUBLIC="$1"

[ -n "$PUBLIC" ] || { echo "usage: tunnel.sh <desktop-public-address>" >&2 ; exit 1 ; }

umask 077
D=$(mktemp -d) || exit 1
trap 'rm -rf "$D" 2>/dev/null || true' EXIT INT TERM HUP

# the two key pairs
wg genkey > "$D/srv.key"
wg pubkey < "$D/srv.key" > "$D/srv.pub"
wg genkey > "$D/tel.key"
wg pubkey < "$D/tel.key" > "$D/tel.pub"

# the phone's peer, written by the desktop, then read by the phone
# the desktop writes in a corner of its own, then pushes : /etc/wireguard belongs to root
cat > "$D/wg0.conf" <<EOF
# THE PHONE TUNNEL. Placed by config/engine/tunnel.sh, re-read by wg-quick.
[Interface]
Address = 10.10.0.1/24
ListenPort = $PORT
PrivateKey = $(cat "$D/srv.key")

[Peer]
# the phone
PublicKey = $(cat "$D/tel.pub")
AllowedIPs = 10.10.0.2/32
EOF
chmod 600 "$D/wg0.conf"
sudo -n mkdir -p /etc/wireguard
sudo -n install -m 600 -o root -g root "$D/wg0.conf" "$CONF"

# the phone's profile : a single peer, the desktop ; its normal traffic does not go through it
cat > "$W/LA-phone.conf" <<EOF
[Interface]
PrivateKey = $(cat "$D/tel.key")
Address = 10.10.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = $(cat "$D/srv.pub")
Endpoint = $PUBLIC:$PORT
AllowedIPs = 10.10.0.0/24
PersistentKeepalive = 25
EOF
chmod 600 "$W/LA-phone.conf"
qrencode -o "$W/LA-phone.png" -r "$W/LA-phone.conf"
chmod 600 "$W/LA-phone.png"

# the interface comes up now, and comes back at boot
sudo -n wg-quick down wg0 >/dev/null 2>&1 || true
sudo -n wg-quick up wg0
sudo -n systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true

echo "the tunnel is up."
sudo -n wg show wg0 | sed -n '1,6p'
echo "--- phone profile : $W/LA-phone.conf"
echo "--- code to scan   : $W/LA-phone.png"
echo "--- desktop public key : $(cat "$D/srv.pub")"
