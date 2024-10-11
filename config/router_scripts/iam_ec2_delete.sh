#!/bin/sh

ROLE_NAME="$1"
REGION="$2"
INSTANCE_PROFILE_NAME="$3"
POLICY_NAME="$4"
AWS_ACCESS_KEY="$5"
AWS_SECRET_KEY="$6"
INSTANCE_ID="$7"
PROJ_DIR="$8"
WAIT=22
PRE_WAIT=105

echo "Waiting ${PRE_WAIT}s..."
sleep $PRE_WAIT

while true; do
TF_EXEC_STATUS=$(curl -s \
  --aws-sigv4 "aws:amz" \
  --user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
  -H "X-Amz-Target: AmazonSSM.GetParameter" \
  -H "Content-Type: application/x-amz-json-1.1" \
  -d '{"Name":"WG_EC2_STATUS"}' \
  "https://ssm.${REGION}.amazonaws.com/" | jq -r '.Parameter.Value'
)

if [[ "$TF_EXEC_STATUS" == "OK" ]]; then
   echo "TF_EXEC server has completed tasks. Terminating..."
   break
 else
   echo "Status: $TF_EXEC_STATUS. Checking again in ${WAIT}s..."
fi
sleep $WAIT
done

echo -e "\n============================="
echo "   Terminate EC2 Instance"
echo "============================="

curl --request POST \
"https://ec2.${REGION}.amazonaws.com/" \
--aws-sigv4 "aws:amz:${REGION}:ec2" \
--user "${AWS_ACCESS_KEY}:${AWS_SECRET_KEY}" \
--header 'Content-Type: application/x-www-form-urlencoded' \
--data-urlencode "Action=TerminateInstances" \
--data-urlencode "InstanceId=${INSTANCE_ID}" \
--data-urlencode "Version=2016-11-15"

"$PROJ_DIR/iam_delete.sh" "$ROLE_NAME" "$REGION" "$INSTANCE_PROFILE_NAME" "$POLICY_NAME" "$AWS_ACCESS_KEY" "$AWS_SECRET_KEY"
