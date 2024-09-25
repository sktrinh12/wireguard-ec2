#!/bin/sh

GPG_PASSPHRASE=$(gpg --batch --yes --decrypt /mnt/creds/input.gpg)
eval $(gpg --batch --yes --passphrase "$GPG_PASSPHRASE" --decrypt /mnt/creds/aws.gpg) 

source ./user_data.sh

ALLOWED_IPS="0.0.0.0/0"
AMI_ID="ami-0e86e20dae9224db8"
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo $CLIENT_PRIVATE_KEY | wg pubkey)
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
BUCKET_NAME="tf-ec2-state"
BUCKET_REGION="us-east-2"
KEY_PREFIX="wireguard"
TERRAFORM_CMD="apply"
USER_DATA_UP=$(echo "$USER_DATA" | awk -v tf="$TERRAFORM_CMD" \
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

USER_DATA_APPEND_IP=$(echo "$USER_DATA_SSM_IP" | awk \
    -v client_public="$CLIENT_PUBLIC_KEY" \
    -v aws_access="$AWS_ACCESS_KEY" \
    -v aws_secret="$AWS_SECRET_KEY" \
    -v region="$REGION" '
{
    gsub("{{CLIENT_PUBLIC_KEY}}", client_public);
    gsub("{{AWS_ACCESS_KEY}}", aws_access);
    gsub("{{AWS_SECRET_KEY}}", aws_secret);
    gsub("{{REGION}}", region);
    print;
}')

USER_DATA_APPEND_SSM=$(echo "$USER_DATA_SSM_STATUS" | awk \
    -v status_name="WG_EC2_STATUS" \
    -v status="OK" \
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

USER_DATA_UP=$(cat << EOF
${USER_DATA_UP}

${USER_DATA_APPEND_IP}

${USER_DATA_APPEND_SSM}
EOF
)

unset USER_DATA_APPEND_SSM
unset USER_DATA_APPEND_IP
# echo "$USER_DATA_UP"
# echo 'press button'
# read -r

USER_DATA_BASE64=$(echo "$USER_DATA_UP" | base64)
./iam_config.sh "$ROLE_NAME" "$REGION" "$POLICY_NAME" "$INSTANCE_PROFILE_NAME" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY" "$BUCKET_NAME"

echo "==============================="
echo "  Waiting for IAM propogation  "
echo "==============================="
sleep 5

./ec2_setup.sh "$AMI_ID" "$CLIENT_PUBLIC_KEY" "$NAME" "$GIT_REPO" "$INSTANCE_PROFILE_NAME" "$INSTANCE_TYPE" "$REGION" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY" "$BUCKET_NAME" "$BUCKET_REGION" "$KEY_PREFIX" "$USER_DATA_BASE64"
 
echo "======================================"
echo "  Waiting for Terraform installation  "
echo "======================================"

INSTANCE_ID=$(cat instance_id)
echo "======================================="
echo "   INSTANCE ID: $INSTANCE_ID"
echo "======================================="

# PUBLIC_IP=$(curl -s "https://ec2.${REGION}.amazonaws.com/" \
#   --header "Content-Type: application/x-www-form-urlencoded" \
#   --user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
#   --data-urlencode "Action=DescribeInstances" \
#   --data-urlencode "InstanceId=${INSTANCE_ID}" \
#   --data-urlencode "Version=2016-11-15" \
#   --aws-sigv4 "aws:amz:${REGION}:ec2" | xmllint --xpath "string(//*[local-name()='ipAddress'])" -
# )

./iam_delete.sh "$ROLE_NAME" "$REGION" "$INSTANCE_PROFILE_NAME" "$POLICY_NAME" "$BUCKET_NAME" "$KEY_PREFIX" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY" "$INSTANCE_ID"

PUBLIC_IP=$(
curl -s \
  --aws-sigv4 "aws:amz" \
  --user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
  -H "X-Amz-Target: AmazonSSM.GetParameter" \
  -H "Content-Type: application/x-amz-json-1.1" \
  -d '{"Name":"PUBLIC_IP"}' \
  "https://ssm.${REGION}.amazonaws.com/" | jq -r '.Parameter.Value'
)

SERVER_PUBLIC_KEY=$(
curl -s \
  --aws-sigv4 "aws:amz" \
  --user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
  -H "X-Amz-Target: AmazonSSM.GetParameter" \
  -H "Content-Type: application/x-amz-json-1.1" \
  -d '{"Name":"SERVER_PUBLIC_KEY","WithDecryption":true}' \
  "https://ssm.${REGION}.amazonaws.com/" | jq -r '.Parameter.Value'
)

echo -e "=========================\nPUBLIC IP AND SERVER KEY\n========================="
echo "Public IP: $PUBLIC_IP"
echo "Server Public Key: $SERVER_PUBLIC_KEY"

echo "$ALLOWED_IPS $CLIENT_PRIVATE_KEY $REGION $IP_ADDRESS $PEER_PORT $PEER_NAME"

./router_config.sh "$ALLOWED_IPS" "$CLIENT_PRIVATE_KEY" "$SERVER_PUBLIC_KEY" "$REGION" "$IP_ADDRESS" "$PEER_PORT" "$PEER_NAME" "$PUBLIC_IP"
