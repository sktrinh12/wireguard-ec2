#!/bin/sh

ROLE_NAME="$1"
REGION="$2"
INSTANCE_PROFILE_NAME="$3"
POLICY_NAME="$4"
AWS_ACCESS_KEY="$5"
AWS_SECRET_KEY="$6"

echo "=============================="
echo "   Remove Role from Instance   "
echo "         Profile               "
echo "=============================="

sleep 1
curl --request POST \
"https://iam.amazonaws.com/" \
--aws-sigv4 "aws:amz:${REGION}:iam" \
--user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
--header 'Content-Type: application/x-www-form-urlencoded' \
--data-urlencode "Action=RemoveRoleFromInstanceProfile" \
--data-urlencode "InstanceProfileName=${INSTANCE_PROFILE_NAME}" \
--data-urlencode "RoleName=${ROLE_NAME}" \
--data-urlencode "Version=2010-05-08"

echo "=============================="
echo "     Delete Instance Profile   "
echo "=============================="

sleep 1

curl --request POST \
"https://iam.amazonaws.com/" \
--aws-sigv4 "aws:amz:${REGION}:iam" \
--user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
--header 'Content-Type: application/x-www-form-urlencoded' \
--data-urlencode "Action=DeleteInstanceProfile" \
--data-urlencode "InstanceProfileName=${INSTANCE_PROFILE_NAME}" \
--data-urlencode "Version=2010-05-08"

echo "=============================="
echo "      Delete Role Policy       "
echo "=============================="

sleep 1

curl --request POST \
"https://iam.amazonaws.com/" \
--aws-sigv4 "aws:amz:${REGION}:iam" \
--user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
--header 'Content-Type: application/x-www-form-urlencoded' \
--data-urlencode "Action=DeleteRolePolicy" \
--data-urlencode "RoleName=${ROLE_NAME}" \
--data-urlencode "PolicyName=${POLICY_NAME}" \
--data-urlencode "Version=2010-05-08"

echo "=============================="
echo "          Delete Role          "
echo "=============================="

sleep 1

curl --request POST \
"https://iam.amazonaws.com/" \
--aws-sigv4 "aws:amz:${REGION}:iam" \
--user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
--header 'Content-Type: application/x-www-form-urlencoded' \
--data-urlencode "Action=DeleteRole" \
--data-urlencode "RoleName=${ROLE_NAME}" \
--data-urlencode "Version=2010-05-08"

echo "=============================="
echo "     IAM configs purged!..."
echo "=============================="
