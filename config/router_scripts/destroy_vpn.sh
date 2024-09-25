#!/bin/sh

GPG_PASSPHRASE=$(gpg --batch --yes --decrypt /mnt/creds/input.gpg)
eval $(gpg --batch --yes --passphrase "$GPG_PASSPHRASE" --decrypt /mnt/creds/aws.gpg)

source ./user_data.sh

AMI_ID="ami-0e86e20dae9224db8"
NAME="wireguard-ec2"
GIT_REPO="https://github.com/sktrinh12/${NAME}.git"
INSTANCE_PROFILE_NAME="tf-exec-instance-profile"
INSTANCE_TYPE="t2.micro"
REGION="us-east-1"
ROLE_NAME="tf-exec-role"
POLICY_NAME="tf-exec-policy"
PEER_NAME="vpn"
BUCKET_NAME="tf-ec2-state"
BUCKET_REGION="us-east-2"
KEY_PREFIX="wireguard" 
STATUS="Not Ready"
TERRAFORM_CMD="destroy"
USER_DATA_DOWN=$(echo "$USER_DATA" | awk -v tf="$TERRAFORM_CMD" \
    -v git="$GIT_REPO" \
    -v nm="$NAME" \
    -v bucket_name="$BUCKET_NAME" \
    -v bucket_region="$BUCKET_REGION" \
    -v key="$KEY_PREFIX" \
    -v client_public="$CLIENT_PUBLIC_KEY" \
    -v aws_access="$AWS_ACCESS_KEY" \
    -v aws_secret="$AWS_SECRET_KEY" \
    -v region="$REGION" '
{
    gsub("{{TERRAFORM_CMD}}", tf);
    gsub("{{GIT_REPO}}", git);
    gsub("{{NAME}}", nm);
    gsub("{{BUCKET_NAME}}", bucket_name);
    gsub("{{BUCKET_REGION}}", bucket_region);
    gsub("{{KEY_PREFIX}}", key);
    gsub("{{CLIENT_PUBLIC_KEY}}", client_public);
    gsub("{{AWS_ACCESS_KEY}}", aws_access);
    gsub("{{AWS_SECRET_KEY}}", aws_secret);
    gsub("{{REGION}}", region);
    print;
}')

USER_DATA_APPEND_SSM=$(echo "$USER_DATA_SSM_STATUS" | awk \
    -v status="OK" \
    -v status_name="WG_EC2_STATUS" \
    -v client_public="$CLIENT_PUBLIC_KEY" \
    -v aws_access="$AWS_ACCESS_KEY" \
    -v aws_secret="$AWS_SECRET_KEY" \
    -v region="$REGION" '
{
    gsub("{{STATUS}}", status);
    gsub("{{STATUS_NAME}}", status_name);
    gsub("{{CLIENT_PUBLIC_KEY}}", client_public);
    gsub("{{AWS_ACCESS_KEY}}", aws_access);
    gsub("{{AWS_SECRET_KEY}}", aws_secret);
    gsub("{{REGION}}", region);
    print;
}')

echo "\r"
USER_DATA_DOWN=$(cat << EOF
${USER_DATA_DOWN}

${USER_DATA_APPEND_SSM}
EOF
)

# echo $USER_DATA_DOWN
USER_DATA_BASE64=$(echo "$USER_DATA_DOWN" | base64)

USER_DATA_APPEND_SSM=$(echo "$USER_DATA_SSM_STATUS" | awk \
    -v status_name="WG_EC2_STATUS" \
    -v status="Not Ready" \
    -v client_public="$CLIENT_PUBLIC_KEY" \
    -v aws_access="$AWS_ACCESS_KEY" \
    -v aws_secret="$AWS_SECRET_KEY" \
    -v region="$REGION" '
{
    gsub("{{STATUS_NAME}}", status_name);
    gsub("{{STATUS}}", status);
    gsub("{{CLIENT_PUBLIC_KEY}}", client_public);
    gsub("{{AWS_ACCESS_KEY}}", aws_access);
    gsub("{{AWS_SECRET_KEY}}", aws_secret);
    gsub("{{REGION}}", region);
    print;
}')

eval "$USER_DATA_APPEND_SSM"
unset USER_DATA_APPEND_SSM

./iam_config.sh "$ROLE_NAME" "$REGION" "$POLICY_NAME" "$INSTANCE_PROFILE_NAME" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY" "$BUCKET_NAME"

echo "==============================="
echo "  Waiting for IAM propogation  "
echo "==============================="
sleep 5

./ec2_setup.sh "$AMI_ID" "$CLIENT_PUBLIC_KEY" "$NAME" "$GIT_REPO" "$INSTANCE_PROFILE_NAME" "$INSTANCE_TYPE" "$REGION" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY" "$BUCKET_NAME" "$BUCKET_REGION" "$KEY_PREFIX" "$USER_DATA_BASE64"

INSTANCE_ID=$(cat instance_id)
echo "======================================="
echo "   INSTANCE ID: $INSTANCE_ID"
echo "======================================="
echo -e "\r"
echo "======================================"
echo "  Waiting for Terraform Destroy       "
echo "======================================"

# router de-config
echo "Deleting ${PEER_NAME}..."
uci -q delete network.${PEER_NAME}
echo "Deleting wgserver..."
uci -q delete network.wgserver 
uci commit network
service network restart

./iam_delete.sh "$ROLE_NAME" "$REGION" "$INSTANCE_PROFILE_NAME" "$POLICY_NAME" "$BUCKET_NAME" "$KEY_PREFIX" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY" "$INSTANCE_ID"
