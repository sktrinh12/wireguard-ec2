#!/bin/bash

# Exit immediately if any command fails
set -e
placeholder=""

# Check for correct number of arguments
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 {up|down} [0|1]"
  exit 1
fi

PUBLIC_IP=""
SERVER_PUBLIC_KEY=""
CLIENT_PUBLIC_KEY=""
CLIENT_PRIVATE_KEY=""
ROUTER_IP="192.168.1.1"
PEER_PORT=51820
ALLOWED_IPS="0.0.0.0/0"
IP_ADDRESS="10.0.0.2/24"
USERNAME="root"
PEER_NAME="vpn"

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

}

# Function to bring down WireGuard VPN
down_vpn() {
    echo "Destroying EC2 WireGuard Terraform deployment..."
    terraform destroy -auto-approve -var "client_public_key=${CLIENT_PUBLIC_KEY}"
    echo "EC2 WireGuard deployment destroyed."
}

remove_device_config() {
    sudo wg-quick down wg0 || true
    echo "WireGuard VPN client de-configured"
}

config_router() {
  echo "configuring router for wireguard VPN"
  ssh "${USERNAME}@${ROUTER_IP}" << EOF
    opkg update
    opkg install wireguard-tools

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
    uci set network.${PEER_NAME}.dns='8.8.8.8 8.8.4.4'
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
EOF
}


config_current_device() {
  echo "configuring current device for wireguard VPN"
  TEMP_CONF=$(mktemp)

  cat <<EOC > $TEMP_CONF
  [Interface]
  Address = ${IP_ADDRESS}
  ListenPort = ${PEER_PORT}
  PrivateKey = ${CLIENT_PRIVATE_KEY}
  DNS = 8.8.8.8, 8.8.4.4

  [Peer]
  PublicKey = ${SERVER_PUBLIC_KEY}
  Endpoint  = ${PUBLIC_IP}:${PEER_PORT}
  AllowedIPs = ${ALLOWED_IPS}
  PersistentKeepalive = 25
EOC

  echo "replacing 'wg0.conf' file"
  sudo cp $TEMP_CONF /etc/wireguard/wg0.conf
  # Clean up the temporary file
  rm $TEMP_CONF
  echo "activating wg interface"
  sudo wg-quick up wg0
}

remove_router_config() {
  echo "Removing WireGuard configuration from router..."
  ssh "$USERNAME@$ROUTER_IP" << EOF
    # Remove the WireGuard interface configuration 
    uci -q delete network.wgserver

    # Remove the peer configuration
    uci delete network.$PEER_NAME

    uci commit network
    service network restart
EOF
}

if [ "$1" = "down" ]; then
  placeholder="de-"
fi

# validate second argument
case "$2" in
  0)
    echo -e "=========================\n${placeholder}configuring for router client\n========================="
    ;;
  1)
    echo -e "=========================\n${placeholder}configuring for current device client\n========================="
    ;;
  *)
    echo -e "=========================\n$2 - is not a valid argument\n========================="
    exit 1
    ;;
esac


# Main logic to handle arguments
case "$1" in
    up)
        up_vpn
        if [ "$2" = "0" ]; then
          config_router
        elif [ "$2" = "1" ]; then
          config_current_device
        fi
        echo -e "=========================\nWIREGUARD CONFIGURED\n========================="
        ;;
    down)
        if [ "$2" = "0" ]; then
          remove_router_config
        elif [ "$2" = "1" ]; then
          remove_device_config
        fi
        down_vpn
        echo -e "=========================\nWIREGUARD DE-CONFIGURED\n========================="
        ;;
    *)
        exit 1
        ;;
esac

# to ensure it is the actual IP address of the current device
PUBLIC_IP=$(curl -sS icanhazip.com)
curl -sS http://ip-api.com/json/$PUBLIC_IP | jq .
cd $cwd
