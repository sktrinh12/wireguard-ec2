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

variable "ami_id" {
  description = "The AMI ID for the instance"
  default     = "ami-0e86e20dae9224db8"
}

variable "instance_type" {
  description = "The instance type for the wireguard server"
  default     = "t2.micro"
}

variable "profile" {
  description = "The AWS profile to use"
  default     = "default"
}
