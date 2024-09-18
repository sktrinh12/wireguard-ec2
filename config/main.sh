#!/bin/bash

# Exit immediately if any command fails
set -e

# Function to handle errors and exit
handle_error() {
  echo "Error occurred. Exiting..."
  exit 1
}

# Trap any errors and call the handle_error function
trap 'handle_error' ERR

cwd=$(pwd)
echo "Changing directory to terraform project..."
cd $HOME/Documents/scripts/terraform/wireguard-ec2

up_vpn() { 
  # generate client keys
  echo "Generating client keys..."
  CLIENT_PRIVATE_KEY=$(wg genkey)
  CLIENT_PUBLIC_KEY=$(echo $CLIENT_PRIVATE_KEY | wg pubkey)

  echo -e "=========================\nCLIENT KEYS GENERATED\n========================="
  echo "Client Private Key: $CLIENT_PRIVATE_KEY"
  echo "Client Public Key: $CLIENT_PUBLIC_KEY"

  # deploy ec2 wireguard
  echo "Deploying EC2 WireGuard with Terraform..."
  terraform apply -auto-approve -var="client_public_key=${CLIENT_PUBLIC_KEY}" || {
  echo "Terraform apply failed."
  exit 1
}

  # retrieve public IP and server public key
  echo "Retrieving public IP and server public key..."
  PUBLIC_IP=$(terraform output -raw public_ip)
  SERVER_PUBLIC_KEY=$(aws ssm get-parameter --name "SERVER_PUBLIC_KEY" --query "Parameter.Value" --output text --with-decryption)

  echo -e "=========================\nPUBLIC IP AND SERVER KEY\n========================="
  echo "Public IP: $PUBLIC_IP"
  echo "Server Public Key: $SERVER_PUBLIC_KEY"

  # Configure WireGuard
  echo "Configuring WireGuard on client..."
  TEMP_CONF=$(mktemp)

  cat <<EOC > $TEMP_CONF
  [Interface]
  Address = 10.0.0.2/24
  ListenPort = 51820
  PrivateKey = ${CLIENT_PRIVATE_KEY}
  DNS = 8.8.8.8, 8.8.4.4

  [Peer]
  PublicKey = ${SERVER_PUBLIC_KEY}
  Endpoint  = ${PUBLIC_IP}:51820
  AllowedIPs = 0.0.0.0/0
  PersistentKeepalive = 25
EOC

  sudo cp $TEMP_CONF /etc/wireguard/wg0.conf

  # Clean up the temporary file
  rm $TEMP_CONF

  echo -e "=========================\nWIREGUARD CONFIGURED\n========================="

  sudo wg-quick up wg0
  echo "WireGuard VPN is up and running."
}

# Function to bring down WireGuard VPN
down_vpn() {
    echo "Tearing down WireGuard VPN..."
    sudo wg-quick down wg0 || true
    echo "WireGuard VPN is down."

    echo "Destroying EC2 WireGuard deployment with Terraform..."
    terraform destroy -auto-approve -var "client_public_key=${CLIENT_PUBLIC_KEY}"
    echo "EC2 WireGuard deployment destroyed."
}

# Main logic to handle arguments
case "$1" in
    up)
        up_vpn
        ;;
    down)
        down_vpn
        ;;
    *)
        echo "Usage: $0 {up|down}"
        exit 1
        ;;
esac

PUBLIC_IP=$(curl -sS icanhazip.com)
curl -sS http://ip-api.com/json/$PUBLIC_IP | jq .
cd $cwd
