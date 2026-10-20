#!/usr/bin/dash
# french in code is forbidden
set -e
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

W="$STATE"   # l etat du harnais, resolu par lib.sh depuis la_config (paths.state)
WGCONF=/etc/wireguard/wg0.conf
PORT=$(conf_num tunnel port 51820)
PUBLIC="$1"

[ -n "$PUBLIC" ] || { echo "usage: tunnel.sh <desktop-public-address>" >&2 ; exit 1 ; }

umask 077
D=$(mktemp -d) || exit 1
trap 'rm -f "$D/srv.key" "$D/srv.pub" "$D/tel.key" "$D/tel.pub" "$D/wg0.conf" ; rmdir "$D" 2>/dev/null || true' EXIT INT TERM HUP

wg genkey > "$D/srv.key"
wg pubkey < "$D/srv.key" > "$D/srv.pub"
wg genkey > "$D/tel.key"
wg pubkey < "$D/tel.key" > "$D/tel.pub"

cat > "$D/wg0.conf" <<EOF
[Interface]
Address = 10.10.0.1/24
ListenPort = $PORT
PrivateKey = $(cat "$D/srv.key")

[Peer]
PublicKey = $(cat "$D/tel.pub")
AllowedIPs = 10.10.0.2/32
EOF
chmod 600 "$D/wg0.conf"
sudo -n mkdir -p /etc/wireguard
sudo -n install -m 600 -o root -g root "$D/wg0.conf" "${WGCONF}"

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

sudo -n wg-quick down wg0 >/dev/null 2>&1 || true
sudo -n wg-quick up wg0
sudo -n systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true

echo "the tunnel is up."
sudo -n wg show wg0 | sed -n '1,6p'
echo "--- phone profile : $W/LA-phone.conf"
echo "--- code to scan   : $W/LA-phone.png"
echo "--- desktop public key : $(cat "$D/srv.pub")"
