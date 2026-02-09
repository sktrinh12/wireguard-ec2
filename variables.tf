variable "client_public_key" {
  description = "Public key of the client"
  type        = string
}

variable "name" {
  description = "Name of entity"
  default     = "wireguard"
}

variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "script_file" {
  description = "Name of script file"
  default     = "setup.sh"
}

variable "script_file_2" {
  description = "Name of script file 2 template"
  default     = "cloudflare-warp.sh.tpl"
}

variable "ami_id" {
  description = "The AMI ID for the instance"
  default     = "ami-0e0115d5655e9f3f9"
}

variable "instance_type" {
  description = "The instance type for the wireguard server"
  default     = "t2.micro"
}

variable "eip_allocation_id" {
  description = "The allocation ID of the Elastic IP"
  type        = string
}

variable "bucket" {
  description = "bucket name of s3"
  type        = string
  default     = "tf-ec2-state-chom"
}

variable "wgcf_private_key" {
  type      = string
  sensitive = true
}

variable "wgcf_public_key" {
  description =  "cloudflare's key"
  type        = string
  default     = "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
}

variable "wgcf_address_v4" {
  type    = string
  default = "172.16.0.2/32"
}

variable "wgcf_address_v6" {
  type    = string
}
