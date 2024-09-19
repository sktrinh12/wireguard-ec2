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

In order for `main.sh` to work without interaction, you will probably need to add these two entries in sudodoers list (`sudo visudo`) in order to run sudo without password prompt. However, this is for current device configuration, not for router configuration:
```
user ALL=(ALL) NOPASSWD: /bin/cp * /etc/wireguard/wg0.conf
user ALL=(ALL) NOPASSWD: /usr/bin/wg-quick *
```

### Router setup using `OpenWRT`

Update to newest firmware by download the `.bin` file from [openwrt downloads](https://downloads.openwrt.org/releases/23.05.4/targets/ramips/mt76x8/). For example, `glinet_gl-mt300n-v2-squashfs-sysupgrade.bin`. Check the sha256sum to ensure the file is valid. 

Deleted section in `/etc/config/wireless`:

```
config wifi-device 'mt7628'
        option type 'mtk'
        option band '2g'
        option htmode 'HT40'
        option channel 'auto'
        option txpower '100'
        option country 'US'
        option disabled '0'
        option legacy_rates '0'
```
due to error: `mt7628(mtk): Interface type not supported
'radio0' is disabled`

In addition set to 0: `uci set wireless.radio0.disabled=0`. And then, `uci commit wireless` and `service network restart`


In order to have password-less ssh access to the gl.inet device (MT300N-V2); generated ssh keys:

```
ssh-keygen -t rsa -b 4096
ssh-copy-id -i ~/.ssh/glinet_mt300.pub root@192.168.8.1
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
```
