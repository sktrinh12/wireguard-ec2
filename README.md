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

### Router setup using `OpenWRT`

Update to newest firmware by download the `.bin` file from [openwrt downloads](https://downloads.openwrt.org/releases/23.05.4/targets/ramips/mt76x8/). For example, `glinet_gl-mt300n-v2-squashfs-sysupgrade.bin`. Check the sha256sum to ensure the file is valid. 

In order to have password-less ssh access to the gl.inet device (MT300N-V2); generated ssh keys:

```
ssh-keygen -t rsa -b 4096
ssh-copy-id -i ~/.ssh/glinet_mt300.pub root@${IP_ADDR_DEVICE}
```

When prompted name the file accordingly, in this case `glinet_mt300` Then copy the public key to the glinet device using the `ssh-copy-id` command.

### Testing the connection

```
traceroute openwrt.org
logread -e vpn
ip route
wg show
wg showconf vpn
ip address show
ip route show table all
logread -e cron
```

To check logs on remote executor EC2 instance, `/var/log/cloud-init-output.log` within AWS Console. Since there won't be ssh access to this ephemeral executor.

### Password protect

```
# this will go thru prompt which you can create a user id
gpg --gen-key
# show available keys
gpg --list-keys
gpg -e -r "${USER_ID}" password.txt
# to decrypt and show it works
gpg -d password.txt.gpg
# in order to decrypt within script
gpg --batch --yes --passphrase "${PASSPHRASE}" -d password.txt
```

### Notes

If you want to clean up resources without using the bash scripts from `/router_scripts` directory, you can use the awscli commands that are written in the `/device_scripts` directory.
