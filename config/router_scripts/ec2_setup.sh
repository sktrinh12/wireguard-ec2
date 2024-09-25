#!/bin/sh

source ./user_data.sh

AMI_ID="$1"
CLIENT_PUBLIC_KEY="$2"
NAME="$3"
GIT_REPO="$4"
INSTANCE_PROFILE_NAME="$5"
INSTANCE_TYPE="$6"
REGION="$7"
AWS_ACCESS_KEY="$8"
AWS_SECRET_KEY="$9"
BUCKET_NAME="${10}"
BUCKET_REGION="${11}"
KEY_PREFIX="${12}"
USER_DATA="${13}"
STATUS="Not Ready"

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
echo -e "\r=============================="
echo "   Deploying EC2 Instance     "
echo "=============================="

curl -s -vvv "https://ec2.${REGION}.amazonaws.com/" \
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
--data-urlencode "TagSpecification.1.ResourceType=instance" \
--data-urlencode "TagSpecification.1.Tag.1.Key=Name" \
--data-urlencode "TagSpecification.1.Tag.1.Value=TfExecutor" \
--data-urlencode "UserData=${USER_DATA}" | xmllint --xpath "string(//*[local-name()='instanceId'])" - > instance_id
