#!/bin/bash

# Inputs
REGION=$1
PROFILE=$2

aws ec2 describe-instances --query "Reservations[*].Instances[*].{InstanceId:InstanceId, Name:Tags[?Key=='Name']|[0].Value, PrivateIpAddress:PrivateIpAddress, PublicIpAddress:PublicIpAddress, LaunchTime:LaunchTime}" \
--output json --region "$REGION" --profile "$PROFILE" | jq '.'
