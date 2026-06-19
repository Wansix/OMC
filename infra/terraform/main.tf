terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

variable "aws_region" {
  default = "ap-northeast-2"
}

variable "aws_profile" {
  default = "terraform-user-my"
}

variable "instance_type" {
  default = "t3.xlarge"
}

# .pem 키 파일 자동 생성 및 로컬 저장
resource "tls_private_key" "omc_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "omc_key" {
  key_name   = "omc-key"
  public_key = tls_private_key.omc_key.public_key_openssh
}

resource "local_file" "omc_key_pem" {
  content         = tls_private_key.omc_key.private_key_pem
  filename        = "${path.module}/omc-key.pem"
  file_permission = "0400"
}

# 보안그룹
resource "aws_security_group" "omc_sg" {
  name        = "omc-security-group"
  description = "OMC application security group"

  # SSH - .pem 키 파일로만 인증
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Gateway API
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP (선택 - Nginx 사용 시)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS (선택 - Nginx 사용 시)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 아웃바운드 전체 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Ubuntu 22.04 LTS 최신 AMI 자동 조회
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical 공식

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# EC2 인스턴스
resource "aws_instance" "omc" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.omc_key.key_name
  vpc_security_group_ids = [aws_security_group.omc_sg.id]

  root_block_device {
    volume_size = 30
  }

  # EC2 시작 시 Docker 자동 설치
  user_data = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    usermod -aG docker ubuntu
    systemctl enable docker
    systemctl start docker
  EOF

  tags = {
    Name = "omc-server"
  }
}

# Elastic IP
resource "aws_eip" "omc_eip" {
  instance = aws_instance.omc.id
  domain   = "vpc"
}

# 출력값 - terraform apply 완료 후 터미널에 표시됨
output "elastic_ip" {
  value       = aws_eip.omc_eip.public_ip
  description = "EC2 Elastic IP - GitHub Secrets EC2_HOST에 등록"
}

output "ssh_command" {
  value       = "ssh -i omc-key.pem ubuntu@${aws_eip.omc_eip.public_ip}"
  description = "SSH 접속 명령어"
}
