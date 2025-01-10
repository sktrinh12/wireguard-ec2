packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "ami_prefix" {
  type    = string
  default = "ubuntu-wireguard-linux-aws"
}

locals {
  timestamp = formatdate("YYYY-DD-MM-hh-mm", timestamp())
}

source "amazon-ebs" "ubuntu-wireguard" {
  ami_name      = "${var.ami_prefix}-${local.timestamp}"
  instance_type = "t2.micro"
  region        = "us-east-1"
  profile = "chom"
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/*ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }
  ssh_username = "ubuntu"
  tags = {
    "MANAGED_BY" = "packer"
  }
}

build {
  name = "vpn-server"
  sources = [
    "source.amazon-ebs.ubuntu-wireguard"
  ]

  provisioner "shell" {
    environment_vars = [
      "MANAGED_BY=packer",
      "DEBIAN_FRONTEND=noninteractive"
    ]
    execute_command = "sudo -S env {{ .Vars }} bash '{{ .Path }}'"
    scripts = [
      "scripts/setup.sh"
    ]
  }

  post-processor "manifest" {
    output = "manifest.json"
    strip_path = true
  }
}
