#!/bin/bash

# Inputs
ROLE_NAME=$1
INSTANCE_PROFILE_NAME=$2
POLICY_NAME=$3
REGION=$4
PROFILE=${5:-default}

# Step 1: Detach and delete the policy from the role
POLICY_ARNS=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query "AttachedPolicies[*].PolicyArn" --output text --region "$REGION" --profile "$PROFILE")

if [ -n "$POLICY_ARNS" ]; then
    for POLICY_ARN in $POLICY_ARNS; do
        aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" --region "$REGION" --profile "$PROFILE"
        aws iam delete-policy --policy-arn "$POLICY_ARN" --region "$REGION" --profile "$PROFILE"
        echo "Deleted policy $POLICY_ARN"
    done
else
    echo "No attached policies to delete."
fi

# Step 2: Delete the inline policy (if exists)
aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" --region "$REGION" --profile "$PROFILE" || echo "No inline policy found."

# Step 3: Remove the role from the instance profile
aws iam remove-role-from-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --role-name "$ROLE_NAME" --region "$REGION" --profile "$PROFILE"|| echo "Role not attached to instance profile."

# Step 4: Delete the instance profile
aws iam delete-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --region "$REGION" --profile "$PROFILE" || echo "Instance profile not found."

# Step 5: Delete the IAM role
aws iam delete-role --role-name "$ROLE_NAME" --region "$REGION" --profile "$PROFILE" || echo "Role not found."
