#!/bin/sh

CLIENT_PUBLIC_KEY="$1"
INSTANCE_PROFILE_NAME="$2"
INSTANCE_TYPE="$3"
REGION="$4"
AWS_ACCESS_KEY="$5"
AWS_SECRET_KEY="$6"
USER_DATA_IN="$7"
PROJ_DIR="$8"
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
echo "        GRAB LATEST AMI       "
echo "=============================="

curl -s "https://ec2.${REGION}.amazonaws.com/?" \
--aws-sigv4 "aws:amz:${REGION}:ec2" \
--user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
--header "Content-Type: application/x-www-form-urlencoded" \
--data-urlencode "Action=DescribeImages" \
--data-urlencode "Version=2016-11-15" \
--data-urlencode "Filter.1.Name=name" \
--data-urlencode "Filter.1.Value.1=ubuntu/images/*ubuntu-jammy-22.04-amd64-server-*" \
--data-urlencode "Filter.2.Name=root-device-type" \
--data-urlencode "Filter.2.Value.1=ebs" \
--data-urlencode "Filter.3.Name=virtualization-type" \
--data-urlencode "Filter.3.Value.1=hvm" \
--data-urlencode "Filter.4.Name=is-public" \
--data-urlencode "Filter.4.Value.1=true" > describe-amis.xml

AMI_ID=$(cat describe-amis.xml | xmllint --xpath "//*[local-name()='item']/*[local-name()='imageId']/text()" - | paste -d' ' - <(cat describe-amis.xml | xmllint --xpath "//*[local-name()='item']/*[local-name()='creationDate']/text()" -) | sort -k2 -r | head -n 1 | awk '{print $1}')

echo $AMI_ID

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
echo -e "\n============================================="

# Validate the CURL output is valid XML
echo "$CURL_OUTPUT" | xmllint --noout -

if [ $? -ne 0 ]; then
    echo "Error: Invalid XML output."
    exit 1
fi

echo $CURL_OUTPUT | xmllint --xpath "string(//*[local-name()='instanceId'])" - > "${PROJ_DIR}/instance_id"
