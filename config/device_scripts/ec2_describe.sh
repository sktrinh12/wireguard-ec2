#!/bin/bash

REGION=$1
PROFILE=$2

BOLD='\033[1m'
CYAN='\033[0;36m'
RESET='\033[0m'

row() {
  printf "  ${BOLD}%-18s${RESET} %s\n" "$1" "$2"
}

DATA=$(aws ec2 describe-instances \
  --query "Reservations[*].Instances[*].{InstanceId:InstanceId, Name:Tags[?Key=='Name']|[0].Value, PrivateIpAddress:PrivateIpAddress, PublicIpAddress:PublicIpAddress, LaunchTime:LaunchTime}" \
  --output json --region "$REGION" --profile "$PROFILE" | jq '[.[][0]]')

COUNT=$(echo "$DATA" | jq 'length')

for i in $(seq 0 $((COUNT - 1))); do
  INSTANCE=$(echo "$DATA" | jq ".[$i]")
  echo -e "  ${CYAN}── Instance $((i + 1)) of ${COUNT} ──────────────────────────${RESET}"
  row "Instance ID"  "$(echo "$INSTANCE" | jq -r '.InstanceId')"
  row "Name"         "$(echo "$INSTANCE" | jq -r '.Name')"
  row "Public IP"    "$(echo "$INSTANCE" | jq -r '.PublicIpAddress // "n/a"')"
  row "Private IP"   "$(echo "$INSTANCE" | jq -r '.PrivateIpAddress // "n/a"')"
  row "Launch Time"  "$(echo "$INSTANCE" | jq -r '.LaunchTime')"
  echo ""
done
