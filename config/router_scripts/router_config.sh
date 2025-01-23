#!/bin/sh

ALLOWED_IPS="$1"
CLIENT_PRIVATE_KEY="$2"
SERVER_PUBLIC_KEY="$3"
REGION="$4"
IP_ADDRESS="$5"
PEER_PORT="$6"
PEER_NAME="$7"
PUBLIC_IP="$8"

# configure router settings
# opkg update
# opkg install wireguard-tools

# Configure firewall
uci rename firewall.@zone[0]="lan"
uci rename firewall.@zone[1]="wan"
uci del_list firewall.wan.network="${PEER_NAME}"
uci add_list firewall.wan.network="${PEER_NAME}"
uci commit firewall
service firewall restart

# Configure WireGuard interface
uci -q delete network.${PEER_NAME}
uci set network.${PEER_NAME}="interface"
uci set network.${PEER_NAME}.proto="wireguard"
uci set network.${PEER_NAME}.private_key="${CLIENT_PRIVATE_KEY}"
uci set network.${PEER_NAME}.dns='1.1.1.1 1.0.0.1'
uci add_list network.${PEER_NAME}.addresses="${IP_ADDRESS}"

 # Configure WireGuard peer
uci -q delete network.wgserver
uci set network.wgserver="wireguard_${PEER_NAME}"
uci set network.wgserver.public_key="${SERVER_PUBLIC_KEY}"
uci set network.wgserver.endpoint_host="${PUBLIC_IP}"
uci set network.wgserver.endpoint_port="${PEER_PORT}"
uci set network.wgserver.persistent_keepalive="25"
uci set network.wgserver.route_allowed_ips="1"
uci add_list network.wgserver.allowed_ips="${ALLOWED_IPS}"
uci add_list network.wgserver.allowed_ips="::/0"
uci commit network
service network restart

PUBLIC_IP=$(curl -s icanhazip.com)
curl -s http://ip-api.com/json/$PUBLIC_IP
