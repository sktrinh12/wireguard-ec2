#!/bin/sh

PEER_NAME="vpn"

uci -q delete network.${PEER_NAME}

 # Configure WireGuard peer
uci -q delete network.wgserver
uci commit network
service network restart
