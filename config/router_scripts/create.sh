#!/bin/sh

set -e

TERRAFORM_CMD="apply"
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo $CLIENT_PRIVATE_KEY | wg pubkey)
PROJ_DIR=$(dirname "$0")
# CURL_TIMEOUT=10
# if [ -f "${PROJ_DIR}/.conf" ]; then
#     source "${PROJ_DIR}/.conf"
# else
#     echo "Configuration file, .conf not found!"
#     exit 1
# fi

if [ -f "$PROJ_DIR/norun.lock" ]; then
    echo "Lock file exists. $0 Exiting..."
    echo "initiated at $(date)"
    exit 0
fi

echo -e "\n====================XX $(basename "$0") started at $(date) XX====================\n"

source "${PROJ_DIR}/variables.sh" "$1"
source "${PROJ_DIR}/user_data.sh"

# EIP_OUTPUT=$(curl -s -v "https://ec2.${REGION}.amazonaws.com/" \
#--aws-sigv4 "aws:amz:${REGION}:ec2" \
#--user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
#--header 'Content-Type: application/x-www-form-urlencoded' \
#--data-urlencode "Action=DescribeAddresses" \
#--data-urlencode "Version=2016-11-15" \
#--max-time $CURL_TIMEOUT
#)

#if [ $? -ne 0 ]; then
#  echo "Failed to retrieve EIP information."
#  exit 1
#fi

#echo $EIP_OUTPUT

#EIP_ALLOC_ID=$(echo "$EIP_OUTPUT" | xmllint --xpath "string(//*[local-name()='addressesSet']/*[local-name()='item']/*[local-name()='allocationId'])" -)

#echo -e "\nEIP ALLOCATION ID: $EIP_ALLOC_ID\n"


curl -s \
  --aws-sigv4 "aws:amz" \
  --user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
  -H "X-Amz-Target: AmazonSSM.PutParameter" \
  -H "Content-Type: application/x-amz-json-1.1" \
  -d '{"Name":"CLIENT_PRIVATE_KEY", "Value": "${CLIENT_PRIVATE_KEY}","Type": "SecureString", "Overwrite": true}' \
  "https://ssm.${REGION}.amazonaws.com/"


USER_DATA_UP=$(echo "$USER_DATA" | awk -v tf="$TERRAFORM_CMD" \
    -v git="$GIT_REPO" \
    -v nm="$NAME" \
    -v bucket_name="$BUCKET_NAME" \
    -v bucket_region="$BUCKET_REGION" \
    -v key="$KEY_PREFIX" \
    -v client_public="$CLIENT_PUBLIC_KEY" \
    -v aws_access="$AWS_ACCESS_KEY" \
    -v aws_secret="$AWS_SECRET_KEY" \
    -v region="$REGION" \
    -v eip_alloc_id="$EIP_ALLOC_ID" '
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
    gsub("{{EIP_ALLOC_ID}}", eip_alloc_id);
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

${USER_DATA_APPEND_SSM}
EOF
)

unset USER_DATA_APPEND_SSM
#unset USER_DATA_APPEND_IP
echo "$USER_DATA_UP"


# delete iam configs
"$PROJ_DIR/iam_delete.sh" "$ROLE_NAME" "$REGION" "$INSTANCE_PROFILE_NAME" "$POLICY_NAME" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY"

"$PROJ_DIR/iam_config.sh" "$ROLE_NAME" "$REGION" "$POLICY_NAME" "$INSTANCE_PROFILE_NAME" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY" "$BUCKET_NAME"

echo -e "\n==============================="
echo "  Waiting for IAM propogation  "
echo "==============================="
sleep 7

"$PROJ_DIR/ec2_setup.sh" "$CLIENT_PUBLIC_KEY" "$INSTANCE_PROFILE_NAME" "$INSTANCE_TYPE" "$REGION" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY" "$USER_DATA_UP" "$PROJ_DIR"
 
echo -e "\n======================================"
echo "  Waiting for Terraform installation  "
echo "======================================"

INSTANCE_ID=$(cat "${PROJ_DIR}/instance_id")
echo -e "\n======================================="
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

#read -r

"${PROJ_DIR}/iam_ec2_delete.sh" "$ROLE_NAME" "$REGION" "$INSTANCE_PROFILE_NAME" "$POLICY_NAME" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY" "$INSTANCE_ID" "$PROJ_DIR"

#echo "Getting PUBLIC_IP & SERVER_PUBLIC_KEY"

#$(echo "$EIP_OUTPUT" | xmllint --xpath "string(//*[local-name()='addressesSet']/*[local-name()='item']/*[local-name()='publicIp'])" - )

SERVER_PUBLIC_KEY=$(
curl -s \
  --aws-sigv4 "aws:amz" \
  --user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
  -H "X-Amz-Target: AmazonSSM.GetParameter" \
  -H "Content-Type: application/x-amz-json-1.1" \
  -d '{"Name":"SERVER_PUBLIC_KEY","WithDecryption":true}' \
  "https://ssm.${REGION}.amazonaws.com/" | jq -r '.Parameter.Value'
)

echo -e "\n=========================\nPUBLIC IP AND SERVER KEY\n========================="
echo "Public IP: $PUBLIC_IP"
echo "Server Public Key: $SERVER_PUBLIC_KEY"


"$PROJ_DIR/router_config.sh" "$ALLOWED_IPS" "$CLIENT_PRIVATE_KEY" "$SERVER_PUBLIC_KEY" "$REGION" "$IP_ADDRESS" "$PEER_PORT" "$PEER_NAME" "$PUBLIC_IP"

echo -e "\n====================================="
echo "  Creation Complete! - $(date)"
echo "====================================="
