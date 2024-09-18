#!/bin/bash
CLIENT_PUBLIC_KEY=$(cat client_public_key)
echo $CLIENT_PUBLIC_KEY

INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')

if [ -z "$INTERFACE" ]; then
  echo "No network interface found. Exiting."
  exit 1
fi

echo "Using network interface: $INTERFACE"

sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y wireguard iptables-persistent curl zip

# install awscli
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws
rm awscliv2.zip

# Generate WireGuard keys
sudo wg genkey | sudo tee /etc/wireguard/server.key | sudo wg pubkey | sudo tee /etc/wireguard/server.pub

# Upload the server public key to AWS SSM Parameter Store
aws ssm put-parameter --name "SERVER_PUBLIC_KEY" --value "$(sudo cat /etc/wireguard/server.pub)" --type "SecureString" --overwrite

# create wg0.conf on server side & enable IP forwarding and NAT
sudo bash -c "cat <<EOC > /etc/wireguard/wg0.conf
  [Interface]
  Address = 10.0.0.1/24
  ListenPort = 51820
  PrivateKey = $(sudo cat /etc/wireguard/server.key)

  PostUp = iptables -t nat -A POSTROUTING -o ${INTERFACE} -j MASQUERADE
  PostUp = iptables -A FORWARD -i wg0 -o ${INTERFACE} -j ACCEPT
  PostUp = iptables -A FORWARD -i ${INTERFACE} -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
  PostDown = iptables -t nat -D POSTROUTING -o ${INTERFACE} -j MASQUERADE
  PostDown = iptables -D FORWARD -i wg0 -o ${INTERFACE} -j ACCEPT
  PostDown = iptables -D FORWARD -i ${INTERFACE} -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

  [Peer]
  PublicKey = ${CLIENT_PUBLIC_KEY}
  AllowedIPs = 10.0.0.2/32
EOC"

sudo sysctl -w net.ipv4.ip_forward=1
sudo sh -c "echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf"
sudo sysctl -p
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
