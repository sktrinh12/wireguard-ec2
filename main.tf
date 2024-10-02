resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "wg_key" {
  key_name   = "${var.name}_ec2_key"
  public_key = tls_private_key.private_key.public_key_openssh
}

resource "local_file" "ssh_private_key" {
  filename = "${path.module}/${var.name}_key.pem"
  content  = tls_private_key.private_key.private_key_pem
  file_permission = "0600"
}


resource "aws_instance" "wireguard" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = aws_key_pair.wg_key.key_name
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name

  provisioner "file" {
    source      = "config/${var.script_file}"
    destination = "/tmp/${var.script_file}"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.private_key.private_key_pem
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/${var.script_file}",
      "echo ${var.client_public_key} > /home/ubuntu/client_public_key",
      "/tmp/${var.script_file}"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.private_key.private_key_pem
      host        = self.public_ip
    }
  }

  tags = {
    Name = "WireGuardServer"
  }

  lifecycle {
    create_before_destroy = true
  }

  security_groups = [aws_security_group.sg.name]
}

resource "aws_iam_role" "ec2_role" {
  name = "ec2_secrets_role_${var.name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "access_policy" {
  name = "access_policy_${var.name}"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = [
          "ssm:PutParameter",
          "ssm:PutParameters"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/SERVER_PUBLIC_KEY"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_role_policy_attach" {
role       = aws_iam_role.ec2_role.name
policy_arn = aws_iam_policy.access_policy.arn
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2_instance_profile_${var.name}"
  role = aws_iam_role.ec2_role.name
}

resource "aws_security_group" "sg" {
  name          = "${var.name}_sg"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 51820 
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
