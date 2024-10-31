#!/bin/sh

USER_DATA=$(cat << EOF
#!/bin/bash
sudo apt-get update -y
sudo apt-get install -y gnupg software-properties-common git wget
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update -y
sudo apt install -y terraform
cd /home/ubuntu
git clone {{GIT_REPO}}
cd {{NAME}}
cat <<EOT > backend.tf
terraform {
  backend "s3" {
    bucket         = "{{BUCKET_NAME}}"
    key            = "{{KEY_PREFIX}}/terraform.tfstate"
    region         = "{{BUCKET_REGION}}"
  }
}
EOT
terraform init -upgrade -reconfigure
terraform {{TERRAFORM_CMD}} -auto-approve -var="client_public_key={{CLIENT_PUBLIC_KEY}}" -var="eip_allocation_id={{EIP_ALLOC_ID}}"
EOF
)

USER_DATA_SSM_STATUS=$(cat << EOF
JSON_PAYLOAD=\$(jq -n --arg name "{{STATUS_NAME}}" --arg value "{{STATUS}}" --arg type "String" \
  '{Name: \$name, Value: \$value, Type: \$type, Overwrite: true}')
echo "==============================="
echo "   SSM set-parameter {{STATUS}}"
echo "==============================="
curl -s \
  --aws-sigv4 "aws:amz" \
  --user "{{AWS_ACCESS_KEY}}:{{AWS_SECRET_KEY}}" \
  -H "X-Amz-Target: AmazonSSM.PutParameter" \
  -H "Content-Type: application/x-amz-json-1.1" \
  -d "\$JSON_PAYLOAD" \
  "https://ssm.{{REGION}}.amazonaws.com/"
EOF
)

# USER_DATA_SSM_IP=$(cat << EOF
# sleep 4
# terraform refresh -var="client_public_key={{CLIENT_PUBLIC_KEY}}"
# echo "==============================="
# echo "  SSM set-parameter PUBLIC_IP  "
# echo "==============================="
# JSON_PAYLOAD=\$(jq -n --arg name "PUBLIC_IP" --arg value "\$(terraform output -raw public_ip)" --arg type "String" \
# '{Name: \$name, Value: \$value, Type: \$type, Overwrite: true}')
#
# curl -v -s \
#   --aws-sigv4 "aws:amz" \
#   --user "{{AWS_ACCESS_KEY}}:{{AWS_SECRET_KEY}}" \
#   -H "X-Amz-Target: AmazonSSM.PutParameter" \
#   -H "Content-Type: application/x-amz-json-1.1" \
#   -d "\$JSON_PAYLOAD" \
#   "https://ssm.{{REGION}}.amazonaws.com/"
# EOF
# )
