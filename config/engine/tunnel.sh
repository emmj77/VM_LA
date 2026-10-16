#!/bin/dash
# tunnel.sh - LE TUNNEL DU TELEPHONE (WireGuard).
#
# POURQUOI : le widget parle a une adresse PRIVEE du poste. Sur le meme reseau, tout marche ;
# en 4G, il n y a aucun chemin. Ce script monte le seul chemin qui existe sans ouvrir le pont
# sur Internet : un tunnel WireGuard entre le telephone et le poste.
#
# CE QU IL POSE, ET RIEN DE PLUS :
#   - l interface wg0 sur le poste, adresse 10.10.0.1/24, port d ecoute 51820/UDP ;
#   - un seul pair : le telephone, 10.10.0.2/32 ;
#   - AUCUN routage, AUCUN NAT, AUCUNE redirection de trafic : le telephone ne fait qu ATTEINDRE
#     le poste. AllowedIPs est borne a 10.10.0.0/24 des deux cotes : la navigation du telephone
#     ne passe pas par ici.
#
# CE QU IL NE PEUT PAS FAIRE : ouvrir le port sur la box. La redirection UDP 51820 vers
# 192.168.8.2 reste un geste de la main de MOUSSA.
#
# LES CLES PRIVEES NE SORTENT JAMAIS : elles vont dans des fichiers, jamais sur la sortie.
set -e
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
W="$ROOT/work"
CONF=/etc/wireguard/wg0.conf
PORT=51820
PUBLIC="$1"

[ -n "$PUBLIC" ] || { echo "usage : tunnel.sh <adresse-publique-du-poste>" >&2 ; exit 1 ; }

umask 077
D=$(mktemp -d) || exit 1
trap 'rm -rf "$D" 2>/dev/null || true' EXIT INT TERM HUP

# les deux paires de cles
wg genkey > "$D/srv.key"
wg pubkey < "$D/srv.key" > "$D/srv.pub"
wg genkey > "$D/tel.key"
wg pubkey < "$D/tel.key" > "$D/tel.pub"

# le pair du telephone, ecrit par le poste, puis lu par le telephone
# le poste ecrit dans un coin a lui, puis pousse : /etc/wireguard appartient a root
cat > "$D/wg0.conf" <<EOF
# LE TUNNEL DU TELEPHONE. Pose par config/engine/tunnel.sh, relu par wg-quick.
[Interface]
Address = 10.10.0.1/24
ListenPort = $PORT
PrivateKey = $(cat "$D/srv.key")

[Peer]
# le telephone
PublicKey = $(cat "$D/tel.pub")
AllowedIPs = 10.10.0.2/32
EOF
chmod 600 "$D/wg0.conf"
sudo -n mkdir -p /etc/wireguard
sudo -n install -m 600 -o root -g root "$D/wg0.conf" "$CONF"

# le profil du telephone : un seul pair, le poste ; son trafic normal ne passe pas dedans
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

# l interface monte maintenant, et remonte au demarrage
sudo -n wg-quick down wg0 >/dev/null 2>&1 || true
sudo -n wg-quick up wg0
sudo -n systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true

echo "le tunnel est monte."
sudo -n wg show wg0 | sed -n '1,6p'
echo "--- profil du telephone : $W/LA-phone.conf"
echo "--- code a scanner   : $W/LA-phone.png"
echo "--- cle publique du poste : $(cat "$D/srv.pub")"
