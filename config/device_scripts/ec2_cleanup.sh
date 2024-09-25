#!/bin/bash

# Inputs
REGION=$1
NAME_TAG=$2

# Step 1: Get Instance IDs
INSTANCE_IDS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$NAME_TAG" --query "Reservations[*].Instances[*].InstanceId" --output text --region "$REGION")

# Delete Security Groups
SECURITY_GROUP_IDS=$(aws ec2 describe-instances --instance-ids $INSTANCE_IDS --query "Reservations[*].Instances[*].SecurityGroups[*].GroupId" --output text --region "$REGION")

if [ -n "$SECURITY_GROUP_IDS" ]; then
  for SG_ID in $SECURITY_GROUP_IDS; do
      aws ec2 delete-security-group --group-id "$SG_ID" --region "$REGION" > /dev/null 2>&1 || echo "Security group $SG_ID could not be deleted."
  done
else
    echo "No dangling security groups found to terminate."
fi

# Delete Subnets
SUBNET_IDS=$(aws ec2 describe-instances --instance-ids $INSTANCE_IDS --query "Reservations[*].Instances[*].SubnetId" --output text --region "$REGION")

if [ -n "$SUBNET_IDS" ]; then
  for SUBNET_ID in $SUBNET_IDS; do
      aws ec2 delete-subnet --subnet-id "$SUBNET_ID" --region "$REGION" > /dev/null 2>&1 || echo "Subnet $SUBNET_ID could not be deleted."
  done
else
    echo "No dangling subnet ids found to terminate."
fi

# Delete EC2 Instance
if [ -n "$INSTANCE_IDS" ]; then
    aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --region "$REGION" > /dev/null 2>&1

    aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS --region "$REGION"
    echo "Terminated instances: $INSTANCE_IDS"
else
    echo "No EC2 instances found to terminate."
fi

