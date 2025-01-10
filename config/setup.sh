#!/bin/bash

CLIENT_PUBLIC_KEY=$(cat client_public_key)

INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')

if [ -z "$INTERFACE" ]; then
  echo "No network interface found. Exiting."
  exit 1
fi

echo "Using network interface: $INTERFACE"

# Generate WireGuard keys
sudo wg genkey | sudo tee /etc/wireguard/server.key | sudo wg pubkey | sudo tee /etc/wireguard/server.pub

# Upload the server public key to AWS SSM Parameter Store
aws ssm put-parameter --name "SERVER_PUBLIC_KEY" --value "$(sudo cat /etc/wireguard/server.pub)" --type "SecureString" --overwrite

# create wg0.conf on server side & enable IP forwarding and NAT
sudo bash -c "cat <<EOC > /etc/wireguard/wg0.conf
  [Interface]
  Address = 10.131.54.1/24, fd11:5ee:bad:c0de::1/64
  ListenPort = 51820
  PrivateKey = $(sudo cat /etc/wireguard/server.key)

  PostUp = iptables -t nat -A POSTROUTING -o ${INTERFACE} -j MASQUERADE
  PostUp = ip6tables -t nat -A POSTROUTING -o ${INTERFACE} -j MASQUERADE
  PostUp = iptables -A FORWARD -i wg0 -o ${INTERFACE} -j ACCEPT
  PostUp = ip6tables -A FORWARD -i wg0 -o ${INTERFACE} -j ACCEPT
  PostUp = iptables -A FORWARD -i ${INTERFACE} -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
  PostUp = ip6tables -A FORWARD -i ${INTERFACE} -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

  PostDown = iptables -t nat -D POSTROUTING -o ${INTERFACE} -j MASQUERADE
  PostDown = ip6tables -t nat -D POSTROUTING -o ${INTERFACE} -j MASQUERADE
  PostDown = iptables -D FORWARD -i wg0 -o ${INTERFACE} -j ACCEPT
  PostDown = ip6tables -D FORWARD -i wg0 -o ${INTERFACE} -j ACCEPT
  PostDown = iptables -D FORWARD -i ${INTERFACE} -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
  PostDown = ip6tables -D FORWARD -i ${INTERFACE} -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

  [Peer]
  PublicKey = ${CLIENT_PUBLIC_KEY}
  AllowedIPs = 10.131.54.2/32, fd11:5ee:bad:c0de::a83:3602/128
EOC"

sudo sysctl -w net.ipv4.ip_forward=1
sudo sh -c "echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf"
sudo sysctl -w net.ipv6.conf.all.forwarding=1
sudo sh -c "echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf"
sudo sysctl -p

# loads the IPv6 kernel module into the Linux kernel
sudo modprobe ipv6

sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
