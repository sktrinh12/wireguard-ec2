output "public_ip" {
  value = aws_instance.wireguard.public_ip
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "ssh_key_s3_url" {
  value = aws_s3_object.ssh_private_key.id
}
