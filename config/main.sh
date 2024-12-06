#!/bin/bash

# Exit immediately if any command fails
set -e
placeholder=""

# Check for correct number of arguments
if [[ "$#" -lt 2 ]]; then
  echo "Usage: $0 {up|down} [0|1] [opt: conf]"
  exit 1
fi

PROFILE="default"
PUBLIC_IP="34.193.198.229"
SERVER_PUBLIC_KEY=""
CLIENT_PUBLIC_KEY=""
CLIENT_PRIVATE_KEY=""
ROUTER_IP="10.12.07.85"
PEER_PORT=51820
ALLOWED_IPS="0.0.0.0/0"
IP_ADDRESS="10.0.0.2/24"
USERNAME="root"
PEER_NAME="vpn"
EIP_ALLOC="eipalloc-0f3204f9f1538ed2f"
DB_NAME="${PEER_NAME}.db"
TABLE_NAME="keys"

# set profile to chom for now
if [ "$2" -eq 1 ]; then
  PROFILE="chom"
fi

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
  sqlite3 $DB_NAME <<EOF
  CREATE TABLE IF NOT EXISTS $TABLE_NAME (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      client_private_key TEXT NOT NULL,
      client_public_key TEXT NOT NULL
  );
EOF

  # generate client keys
  echo "Generating client keys..."
  CLIENT_PRIVATE_KEY=$(wg genkey)
  CLIENT_PUBLIC_KEY=$(echo $CLIENT_PRIVATE_KEY | wg pubkey)

  echo -e "=========================\nCLIENT KEYS GENERATED\n========================="
  echo "Client Private Key: $CLIENT_PRIVATE_KEY"
  echo "Client Public Key: $CLIENT_PUBLIC_KEY"

  sqlite3 $DB_NAME <<EOF
DELETE FROM $TABLE_NAME;
INSERT INTO $TABLE_NAME (client_private_key, client_public_key)
VALUES ('$CLIENT_PRIVATE_KEY', '$CLIENT_PUBLIC_KEY');
EOF

  echo "Keys have been saved to $DB_NAME."

  # deploy ec2 wireguard
  echo "Deploying EC2 WireGuard with Terraform..."
  AWS_PROFILE=${PROFILE} terraform init --reconfigure
  AWS_PROFILE=${PROFILE} terraform apply -auto-approve -var="client_public_key=${CLIENT_PUBLIC_KEY}" -var="eip_allocation_id=${EIP_ALLOC}" || {
  echo "Terraform apply failed."
  exit 1
}

  # retrieve public IP and server public key
  # echo "Retrieving public IP and server public key..."
  # PUBLIC_IP=$(terraform output -raw public_ip)
  SERVER_PUBLIC_KEY=$(aws ssm get-parameter --name "SERVER_PUBLIC_KEY" --query "Parameter.Value" --output text --with-decryption --profile $PROFILE)

  echo -e "=========================\nPUBLIC IP AND SERVER KEY\n========================="
  echo "Public IP: $PUBLIC_IP"
  echo "Server Public Key: $SERVER_PUBLIC_KEY"

}

read_keys() {
  local result
  result=$(sqlite3 $DB_NAME "SELECT client_private_key, client_public_key FROM $TABLE_NAME ORDER BY id DESC LIMIT 1;")

  CLIENT_PRIVATE_KEY=$(echo "$result" | cut -d '|' -f 1)
  CLIENT_PUBLIC_KEY=$(echo "$result" | cut -d '|' -f 2)
}

# Function to bring down WireGuard VPN
down_vpn() {
    echo "Destroying EC2 WireGuard Terraform deployment..."
    AWS_PROFILE=${PROFILE} terraform destroy -auto-approve -var "client_public_key=${CLIENT_PUBLIC_KEY}" -var "eip_allocation_id=${EIP_ALLOC}"
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
        if [[ -n $3 ]]; then
          echo "Argument for configuration: $3"
        else
          up_vpn
        fi

        read_keys

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
        if [[ -n $3 ]]; then
          echo "Argument for configuration: $3"
        else
          down_vpn
        fi
        echo -e "=========================\nWIREGUARD DE-CONFIGURED\n========================="
        ;;
    *)
        exit 1
        ;;
esac

cd $cwd
