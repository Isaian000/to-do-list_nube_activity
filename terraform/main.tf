terraform {
  required_version = ">= 1.10"

  # estado en s3, bucket y key via -backend-config en init
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region
}

# ---------- variables ----------

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "repo_url" {
  description = "Repositorio público que la instancia clona al arrancar"
  type        = string
  default     = "https://github.com/Isaian000/to-do-list_nube_activity.git"
}

variable "repo_branch" {
  type    = string
  default = "main"
}

variable "public_key" {
  description = "Contenido de la llave pública SSH que se sube como Key Pair (secret SSH_PUBLIC_KEY)"
  type        = string

  validation {
    condition     = length(trimspace(var.public_key)) > 0
    error_message = "public_key no puede estar vacía."
  }
}

variable "ssh_cidr" {
  description = "Desde dónde se permite SSH (idealmente tu IP/32)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "app_port" {
  type    = number
  default = 8000
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "db_name" {
  type    = string
  default = "todolist"
}

variable "db_username" {
  type    = string
  default = "todoadmin"
}

# ---------- red (vpc por defecto) ----------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ---------- ami amazon linux 2023 ----------

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

# ---------- key pair ----------

resource "aws_key_pair" "app" {
  key_name   = "to-do-list-key"
  public_key = var.public_key
}

# ---------- security groups ----------

resource "aws_security_group" "app" {
  name        = "to-do-list-app-sg"
  description = "SSH y puerto de la API"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  ingress {
    description = "API"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name        = "to-do-list-db-sg"
  description = "PostgreSQL solo desde la instancia de la app"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "PostgreSQL desde la app"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------- rds ----------

resource "random_password" "db" {
  length  = 20
  special = true
  # solo caracteres seguros para la url y rds
  override_special = "-_"
}

resource "aws_db_subnet_group" "db" {
  name       = "to-do-list-db-subnets"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "db" {
  identifier             = "to-do-list-db"
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
}

# ---------- ec2 + user_data ----------

resource "aws_instance" "app" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.app.key_name
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    repo_url     = var.repo_url
    repo_branch  = var.repo_branch
    app_port     = var.app_port
    database_url = "postgresql+pg8000://${var.db_username}:${random_password.db.result}@${aws_db_instance.db.address}:5432/${var.db_name}"
  })
  user_data_replace_on_change = true

  tags = {
    Name = "to-do-list-api"
  }
}

# ---------- outputs ----------

output "public_ip" {
  value = aws_instance.app.public_ip
}

output "tasks_url" {
  value = "http://${aws_instance.app.public_ip}:${var.app_port}/tasks"
}

output "ssh_command" {
  value = "ssh ec2-user@${aws_instance.app.public_ip}"
}

output "db_endpoint" {
  value = aws_db_instance.db.address
}
