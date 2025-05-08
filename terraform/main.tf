terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region     = "ap-southeast-2"
  access_key = "access_key"
  secret_key = "secret_key"
}

resource "aws_vpc" "prod" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "prod-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.prod.id
  tags = { Name = "prod-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.prod.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-southeast-2a"
  map_public_ip_on_launch = true
  tags = { Name = "public-subnet" }
}

resource "aws_subnet" "private_mysql_source" {
  vpc_id            = aws_vpc.prod.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-southeast-2a"
  tags = { Name = "private-mysql-source" }
}

resource "aws_subnet" "private_mysql_clone" {
  vpc_id            = aws_vpc.prod.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-southeast-2a"
  tags = { Name = "private-mysql-clone" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.prod.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  vpc = true
  tags = { Name = "nat-eip" }
}

resource "aws_nat_gateway" "natgw" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags = { Name = "natgw" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.prod.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.natgw.id
  }
  tags = { Name = "private-rt" }
}

resource "aws_route_table_association" "private_mysql_source" {
  subnet_id      = aws_subnet.private_mysql_source.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_mysql_clone" {
  subnet_id      = aws_subnet.private_mysql_clone.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "bastion" {
  name   = "bastion-sg"
  vpc_id = aws_vpc.prod.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["yourIP/32"]
  }

  #sementara untuk proxy nginx ke phpmyadmin
  ingress {
    from_port   = 80
    to_port     = 80
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

resource "aws_security_group" "mysql" {
  name   = "mysql-sg"
  vpc_id = aws_vpc.prod.id

ingress {
  description = "MySQL access from Bastion"
  from_port   = 3306
  to_port     = 3306
  protocol    = "tcp"
  security_groups = [aws_security_group.bastion.id]
}

  ingress {
    description = "SSH from Bastion"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description = "HTTP from Bastion/Nginx"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description = "MySQL Replication"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "bastion" {
  ami                    = "your-ami"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  associate_public_ip_address = true
  key_name               = "main-key"
  tags = { Name = "BastionHost" }
}

resource "aws_eip" "bastion" {
  vpc      = true
  instance = aws_instance.bastion.id
  tags     = { Name = "bastion-eip" }
}



resource "aws_instance" "mysql_source" {
  ami                    = "your-ami"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_mysql_source.id
  vpc_security_group_ids = [aws_security_group.mysql.id]
  associate_public_ip_address = false
  key_name               = "main-key"
  tags = { Name = "MySQL-Source" }
}

resource "aws_instance" "mysql_clone" {
  ami                    = "your-ami"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_mysql_clone.id
  vpc_security_group_ids = [aws_security_group.mysql.id]
  associate_public_ip_address = false
  key_name               = "main-key"
  tags = { Name = "MySQL-Clone" }
}

output "bastion_public_ip" {
  value = aws_eip.bastion.public_ip
}

output "bastion_private_ip" {
  value = aws_eip.bastion.private_ip
}

output "master_source_private_ip" {
  value = aws_instance.mysql_source.private_ip
}

output "master_source_private_dns" {
  value = aws_instance.mysql_source.private_dns
}

output "mysql_clone_private_dns" {
  value = aws_instance.mysql_clone.private_dns
}

output "mysql_clone_private_ip" {
  value = aws_instance.mysql_clone.private_ip
}