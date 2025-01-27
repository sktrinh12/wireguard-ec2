#!/bin/sh

STATUS="Not Ready"
TERRAFORM_CMD="destroy"
PROJ_DIR=$(dirname "$0")

if [ -f "$PROJ_DIR/norun.lock" ]; then
    echo "Lock file exists. $0 - Exiting..." 
    exit 0
fi

echo -e "\n====================XX $(basename "$0") started at $(date) XX====================\n"

source "${PROJ_DIR}/variables.sh" "$1"
source "${PROJ_DIR}/user_data.sh"

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

# append to USER_DATA_DOWN
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

USER_DATA_DOWN=$(cat << EOF
${USER_DATA_DOWN}

${USER_DATA_APPEND_SSM}
EOF
)

# echo $USER_DATA_DOWN

# re-use var to send curl command now
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

"${PROJ_DIR}/iam_config.sh" "$ROLE_NAME" "$REGION" "$POLICY_NAME" "$INSTANCE_PROFILE_NAME" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY" "$BUCKET_NAME"

echo -e "\n==============================="
echo "  Waiting for IAM propogation  "
echo "==============================="
sleep 4

"${PROJ_DIR}/ec2_setup.sh" "$CLIENT_PUBLIC_KEY" "$INSTANCE_PROFILE_NAME" "$INSTANCE_TYPE" "$REGION" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY" "$USER_DATA_DOWN" "$PROJ_DIR"

INSTANCE_ID=$(cat "${PROJ_DIR}/instance_id")
echo -e "\n======================================="
echo "   INSTANCE ID: $INSTANCE_ID"
echo -e "\n======================================"
echo "  Waiting for Terraform Destroy       "
echo "======================================"

# router de-config
echo "Deleting ${PEER_NAME}..."
uci -q delete network.${PEER_NAME}
echo "Deleting wgserver..."
uci -q delete network.wgserver 
uci commit network
service network restart

"${PROJ_DIR}/iam_ec2_delete.sh" "$ROLE_NAME" "$REGION" "$INSTANCE_PROFILE_NAME" "$POLICY_NAME" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY" "$INSTANCE_ID" "$PROJ_DIR"

echo -e "\n==========================================="
echo "  Destruction Complete! - $(date)"
echo "==========================================="

if [ "${2:-0}" -eq 1 ]; then
    echo "Powering off the device..."
    poweroff
else
    echo "The device will stay on"
fi
