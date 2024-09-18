#### Client

To just test interactively in terminal, first generate client keys:
```bash
CIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo $CLIENT_PRIVATE_KEY | wg pubkey)
```

Then pass to terraform argument: 
```bash
terraform apply -auto-approve -var="client_public_key=${CLIENT_PUBLIC_KEY}"
```

All of the steps are laid out in `main.sh` which can be wrapped in a `zsh` function:

```bash
wvpn() {
  SCRIPT_PATH=path/to/terraform/project
  if [ "$1"=="up" ]; then
      "$SCRIPT_PATH/main.sh" "$1" 
  elif [ "$1"=="down" ]; then
      "$SCRIPT_PATH/main.sh" "$1" 
  else
      echo "Invalid argument: $1. Use 'up' to start or 'down' to stop the VPN."
  fi
}
```

In order for `main.sh` to work without interaction, you will probably need to add these two entries in sudodoers list (`sudo visudo`) in order to run sudo without password prompt:
```
user ALL=(ALL) NOPASSWD: /bin/cp /etc/wireguard/wg0.conf
user ALL=(ALL) NOPASSWD: /usr/bin/wg-quick
```
