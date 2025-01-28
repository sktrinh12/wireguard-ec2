#!/bin/bash

# $1 up or down
# $2 device or router
# $3 profile
# $4 table name (ohio); also bypass up_vpn / down_vpn just to re-configure

# Exit immediately if any command fails
set -e
placeholder=""

# Check for correct number of arguments
if [[ "$#" -lt 2 ]]; then
  echo "Usage: $0 {up|down} {router|device} [opt: profile] [opt: table name]"
  exit 1
fi

PROFILE="default"
PUBLIC_IP="34.193.198.229"
SERVER_PUBLIC_KEY=""
CLIENT_PUBLIC_KEY=""
CLIENT_PRIVATE_KEY=""
ROUTER_IP="192.168.1.1"
PEER_PORT=51820
ALLOWED_IPS=("0.0.0.0/0" "::0/0")
IP_ADDRESS="10.131.54.2/24"
USERNAME="root"
PEER_NAME="vpn"
EIP_ALLOC="eipalloc-0f3204f9f1538ed2f"
DB_NAME="${PEER_NAME}.db"
DNS=("1.1.1.1" "1.0.0.1")
TABLE_NAME="keys"

# set profile to chom for now
if [[ -n "$3" ]]; then
  PROFILE="$3"
fi
echo "Using profile: $PROFILE"

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

  if [[ "$1" == "ohio" ]]; then
    table_name="keys_$1"
  else
    table_name="$TABLE_NAME"
  fi

  local second_column="client_public_key"
  if [[ "$1" == "ohio" ]]; then
    second_column="server_public_key"
  fi

  result=$(sqlite3 $DB_NAME "SELECT client_private_key, $second_column FROM $table_name ORDER BY id DESC LIMIT 1;")
  CLIENT_PRIVATE_KEY=$(echo "$result" | cut -d '|' -f 1)

  if [[ "$1" == "ohio" ]]; then
    SERVER_PUBLIC_KEY=$(echo "$result" | cut -d '|' -f 2)
    PUBLIC_IP="strinhvpn.duckdns.org"
  else
    CLIENT_PUBLIC_KEY=$(echo "$result" | cut -d '|' -f 2)
  fi
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
  dns_commands=""
  for dns in "${DNS[@]}"; do
      dns_commands+="uci add_list network.${PEER_NAME}.dns=$dns"$'\n'
  done

  ip_commands=""
  for ip in "${ALLOWED_IPS[@]}"; do
      ip_commands+="uci add_list network.wgserver.allowed_ips=$ip"$'\n'
  done

  ssh "${USERNAME}@${ROUTER_IP}" << EOF
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
    $(echo -e "${dns_commands}")
    uci add_list network.${PEER_NAME}.addresses="${IP_ADDRESS}"

     # Configure WireGuard peer
    uci -q delete network.wgserver
    uci set network.wgserver="wireguard_${PEER_NAME}"
    uci set network.wgserver.public_key="${SERVER_PUBLIC_KEY}"
    uci set network.wgserver.endpoint_host="${PUBLIC_IP}"
    uci set network.wgserver.endpoint_port="${PEER_PORT}"
    uci set network.wgserver.persistent_keepalive="25"
    uci set network.wgserver.route_allowed_ips="1"
    $(echo -e "${ip_commands}")
    uci commit network
    service network restart
EOF
}


config_current_device() {
  echo "configuring current device for wireguard VPN"
  TEMP_CONF=$(mktemp)
  dns_ips=""
  for dns in "${DNS[@]}"; do
    if [ -z "$dns_ips" ]; then
      dns_ips="$dns"
    else dns_ips+=",$dns"
    fi
  done

  allowed_ips=""
  for ip in "${ALLOWED_IPS[@]}"; do
    if [ -z "$allowed_ips" ]; then
      allowed_ips="$ip"
    else allowed_ips+=",$ip"
    fi
  done

  cat <<EOC > $TEMP_CONF
  [Interface]
  Address = ${IP_ADDRESS}
  ListenPort = ${PEER_PORT}
  PrivateKey = ${CLIENT_PRIVATE_KEY}
  DNS = $dns_ips

  [Peer]
  PublicKey = ${SERVER_PUBLIC_KEY}
  Endpoint  = ${PUBLIC_IP}:${PEER_PORT}
  AllowedIPs = $allowed_ips
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
  router)
    echo -e "=========================\n${placeholder}configuring for router client\n========================="
    ;;
  device)
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
        if [[ -n $4 ]]; then
          echo "table name suffix: $4"
        else
          up_vpn
        fi

        read_keys "$4"

        if [ "$2" = "router" ]; then
          config_router
        elif [ "$2" = "device" ]; then
          if [[ "$4" == "ohio" ]]; then
            sudo wg-quick up strinhcol
          else
            config_current_device
          fi
        fi
        echo -e "=========================\nWIREGUARD CONFIGURED\n========================="
        ;;
    down)
        if [ "$2" = "router" ]; then
          remove_router_config
        elif [ "$2" = "device" ]; then
          if [[ "$4" == "ohio" ]]; then
              sudo wg-quick down strinhcol
          else
            remove_device_config
            down_vpn
          fi
        fi
        echo -e "=========================\nWIREGUARD DE-CONFIGURED\n========================="
        ;;
    *)
        exit 1
        ;;
esac

cd $cwd
