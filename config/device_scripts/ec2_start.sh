#!/bin/bash

# Inputs
AMI_ID=$1
INSTANCE_TYPE=$2
USER_DATA=$3
REGION=$4
INSTANCE_PROFILE_NAME=$5
NAME_TAG=$6

# Step 1: Launch EC2 Instance
aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --user-data "$USER_DATA" \
    --region "$REGION" \
    --iam-instance-profile Name="$INSTANCE_PROFILE_NAME" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME_TAG}]" > /dev/null 2>&1

echo "EC2 Instance launched with Name: $NAME_TAG"

# need about 30 seconds for terraform to install and apply
sleep 30
