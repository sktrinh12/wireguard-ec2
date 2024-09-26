#!/bin/sh

FILE_NAME=$(basename "$0")
echo -e "\n====================XX ${FILE_NAME} started at $(date) XX====================\n" >> "/mnt/logs/${FILE_NAME}.log"

TERRAFORM_CMD="apply"
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo $CLIENT_PRIVATE_KEY | wg pubkey)
PROJ_DIR=$(dirname "$0")

source "${PROJ_DIR}/variables.sh"
source "${PROJ_DIR}/user_data.sh"

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

"$PROJ_DIR/iam_config.sh" "$ROLE_NAME" "$REGION" "$POLICY_NAME" "$INSTANCE_PROFILE_NAME" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY" "$BUCKET_NAME"

echo -e "\n==============================="
echo "  Waiting for IAM propogation  "
echo "==============================="
sleep 4

"$PROJ_DIR/ec2_setup.sh" "$AMI_ID" "$CLIENT_PUBLIC_KEY" "$INSTANCE_PROFILE_NAME" "$INSTANCE_TYPE" "$REGION" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY" "$USER_DATA_UP" "$PROJ_DIR"
 
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

"$PROJ_DIR/iam_delete.sh" "$ROLE_NAME" "$REGION" "$INSTANCE_PROFILE_NAME" "$POLICY_NAME" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY" "$INSTANCE_ID"

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

echo -e "\n=========================\nPUBLIC IP AND SERVER KEY\n========================="
echo "Public IP: $PUBLIC_IP"
echo "Server Public Key: $SERVER_PUBLIC_KEY"

"$PROJ_DIR/router_config.sh" "$ALLOWED_IPS" "$CLIENT_PRIVATE_KEY" "$SERVER_PUBLIC_KEY" "$REGION" "$IP_ADDRESS" "$PEER_PORT" "$PEER_NAME" "$PUBLIC_IP"

echo -e "\n====================================="
echo "  Creation Complete! - $(date)"
echo "====================================="
