#!/bin/sh

AMI_ID="$1"
CLIENT_PUBLIC_KEY="$2"
INSTANCE_PROFILE_NAME="$3"
INSTANCE_TYPE="$4"
REGION="$5"
AWS_ACCESS_KEY="$6"
AWS_SECRET_KEY="$7"
USER_DATA_IN="$8"
PROJ_DIR="$9"
STATUS="Not Ready"

source "$PROJ_DIR/user_data.sh"

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
echo -e "\n=============================="
echo "   Deploying EC2 Instance     "
echo "=============================="

# echo "${USER_DATA_IN}"
USER_DATA_BASE64=$(echo "$USER_DATA_IN" | base64)

CURL_OUTPUT=$(curl -s -vvv "https://ec2.${REGION}.amazonaws.com/" \
--aws-sigv4 "aws:amz:${REGION}:ec2" \
--user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
--header 'Content-Type: application/x-www-form-urlencoded,' \
--data-urlencode "Action=RunInstances" \
--data-urlencode "ImageId=${AMI_ID}" \
--data-urlencode "MaxCount=1" \
--data-urlencode "MinCount=1" \
--data-urlencode "IamInstanceProfile.Name=${INSTANCE_PROFILE_NAME}" \
--data-urlencode "Version=2016-11-15" \
--data-urlencode "InstanceType=${INSTANCE_TYPE}" \
--data-urlencode "KeyName=aws-ec2" \
--data-urlencode "TagSpecification.1.ResourceType=instance" \
--data-urlencode "TagSpecification.1.Tag.1.Key=Name" \
--data-urlencode "TagSpecification.1.Tag.1.Value=TfExecutor" \
--data-urlencode "UserData=${USER_DATA_BASE64}")

echo -e "\n============================================="
echo $CURL_OUTPUT
echo -e "\n=============================================\n"

# Validate the CURL output is valid XML
echo "$CURL_OUTPUT" | xmllint --noout -

if [ $? -ne 0 ]; then
    echo "Error: Invalid XML output."
    exit 1
fi

echo $CURL_OUTPUT | xmllint --xpath "string(//*[local-name()='instanceId'])" - > "${PROJ_DIR}/instance_id"
