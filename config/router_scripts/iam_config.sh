#!/bin/sh

ROLE_NAME="$1"
REGION="$2"
POLICY_NAME="$3"
INSTANCE_PROFILE_NAME="$4"
AWS_ACCESS_KEY="$5"
AWS_SECRET_KEY="$6"
BUCKET_NAME="$7"

ASSUME_ROLE_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

echo "=============================="
echo "       Creating IAM role      "
echo "=============================="
curl --request POST \
"https://iam.amazonaws.com/" \
--aws-sigv4 "aws:amz:${REGION}:iam" \
--user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
--header 'Content-Type: application/x-www-form-urlencoded' \
--data-urlencode "Action=CreateRole" \
--data-urlencode "RoleName=${ROLE_NAME}" \
--data-urlencode "AssumeRolePolicyDocument=${ASSUME_ROLE_POLICY}" \
--data-urlencode "Version=2010-05-08"

echo "creating policy"
sleep 1

ROLE_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:DescribeInstances",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeKeyPairs",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeInstanceCreditSpecifications",
        "ec2:DescribeInstanceAttribute",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:ImportKeyPair",
        "ec2:DeleteKeyPair",
        "ec2:DescribeNetworkInterfaces",
        "ec2:CreateTags",
        "ec2:AssociateAddress",
        "ec2:DescribeAddresses",
        "iam:CreateRole",
        "iam:GetRole",
        "iam:GetPolicy",
        "iam:GetInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:CreateInstanceProfile",
        "iam:CreatePolicy",
        "iam:GetPolicyVersion",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:ListPolicyVersions",
        "iam:ListInstanceProfilesForRole",
        "iam:PassRole",
        "iam:AddRoleToInstanceProfile",
	"iam:RemoveRoleFromInstanceProfile",
        "iam:DeleteRole",
        "iam:DeletePolicy"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": [ "arn:aws:s3:::${BUCKET_NAME}",
       "arn:aws:s3:::${BUCKET_NAME}/*"]
    }
  ]
}
EOF
)

echo "=============================="
echo "      Adding Role Policy      "
echo "=============================="

sleep 1

curl --request POST \
"https://iam.amazonaws.com/" \
--aws-sigv4 "aws:amz:${REGION}:iam" \
--user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
--header 'Content-Type: application/x-www-form-urlencoded' \
--data-urlencode "Action=PutRolePolicy" \
--data-urlencode "RoleName=${ROLE_NAME}" \
--data-urlencode "PolicyName=${POLICY_NAME}" \
--data-urlencode "PolicyDocument=${ROLE_POLICY}" \
--data-urlencode "Version=2010-05-08"

echo "================================"
echo "   Creating instance profile    "
echo "================================"

sleep 1

curl --request POST \
"https://iam.amazonaws.com/" \
--aws-sigv4 "aws:amz:${REGION}:iam" \
--user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
--header 'Content-Type: application/x-www-form-urlencoded' \
--data-urlencode "Action=CreateInstanceProfile" \
--data-urlencode "InstanceProfileName=${INSTANCE_PROFILE_NAME}" \
--data-urlencode "Version=2010-05-08"

echo "============================================"
echo "     Attaching role to instance profile     "
echo "============================================"

sleep 1

curl --request POST \
"https://iam.amazonaws.com/" \
--aws-sigv4 "aws:amz:${REGION}:iam" \
--user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
--header 'Content-Type: application/x-www-form-urlencoded' \
--data-urlencode "Action=AddRoleToInstanceProfile" \
--data-urlencode "InstanceProfileName=${INSTANCE_PROFILE_NAME}" \
--data-urlencode "RoleName=${ROLE_NAME}" \
--data-urlencode "Version=2010-05-08"

echo "=============================="
echo "     IAM tasks completed      "
echo "=============================="
