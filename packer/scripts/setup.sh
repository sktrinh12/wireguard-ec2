#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections

sudo apt-get update
sudo apt-get install -y wireguard iptables-persistent curl unzip jq

TMPDIR=$(mktemp -d)
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$TMPDIR/awscliv2.zip"
unzip -q "$TMPDIR/awscliv2.zip" -d "$TMPDIR"
sudo "$TMPDIR/aws/install" --update
rm -rf "$TMPDIR"

sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
