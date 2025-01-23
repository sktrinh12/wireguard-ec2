#!/bin/sh

ALLOWED_IPS="0.0.0.0/0"
REGION="us-east-1"
NAME="wireguard-ec2"
GIT_REPO="https://github.com/sktrinh12/${NAME}.git"
INSTANCE_PROFILE_NAME="tf-exec-instance-profile"
INSTANCE_TYPE="t2.micro"
IP_ADDRESS="10.0.0.2/24"
PEER_PORT=51820
POLICY_NAME="tf-exec-policy"
PEER_NAME="vpn"
ROLE_NAME="tf-exec-role"
KEY_PREFIX="wireguard"
CREDS_PATH="/root/creds"
EIP_ALLOC_ID="eipalloc-0f3204f9f1538ed2f"
GPG_PASSPHRASE=$(cat ${CREDS_PATH}/input.txt)

if [ "$1" == "1" ]; then
    GPG_FILE="${CREDS_PATH}/aws_chom.gpg"
    BUCKET_NAME="tf-ec2-state-chom"
    BUCKET_REGION="us-east-1"
else
    GPG_FILE="${CREDS_PATH}/aws.gpg"
    BUCKET_NAME="tf-ec2-state"
    BUCKET_REGION="us-east-2"
fi

eval $(gpg --batch --yes --passphrase "$GPG_PASSPHRASE" --decrypt $GPG_FILE)
