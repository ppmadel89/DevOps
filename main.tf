terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}
# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}
# Create a VPC
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    "Name" = "tf_vpc"
  }
}
# create IGW
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "tf_igw"
  }
}
# create Route Table
resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "tf-rt"
  }
}
# create Public Subnet
resource "aws_subnet" "pub_subnet" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.0.1.0/24"
  tags = {
    Name = "pub-tf-subnet"
  }
}
resource "aws_route_table_association" "sub_association" {
  subnet_id      = aws_subnet.pub_subnet.id
  route_table_id = aws_route_table.route_table.id
}
# Create Security Group
resource "aws_security_group" "ssh_https_sg" {
  name        = "Allow_https_ssh"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    description      = "TLS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = [aws_vpc.vpc.cidr_block]
  }
  egress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
ingress {
    description      = "ssh traffic"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = [aws_vpc.vpc.cidr_block]
  }
  egress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Allow_https_ssh"
  }
}
resource "aws_security_group" "db_sg" {
  name        = "allow traffic"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    description      = "TLS from VPC"
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups      = [aws_db_subnet_group.rds_subnet_grp.id]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  tags = {
    Name = "allow_tls"
  }
}
# Create Private Subnet
resource "aws_subnet" "priv_subnet" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.0.2.0/24"
  tags = {
    Name = "priv-tf-subnet"
  }
}
resource "aws_subnet" "priv2_subnet" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.0.3.0/24"
  tags = {
    Name = "priv2-tf-subnet"
  }
}
# Create NAT gateway
resource "aws_eip" "eip" {
#  instance = aws_instance.web.id
#  vpc      = true
}
resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.pub_subnet.id
  tags = {
    Name = "tf-ngw"
  }
  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.igw]
}
resource "aws_route_table" "ngw_rt" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = aws_subnet.priv_subnet.cidr_block
    gateway_id = aws_nat_gateway.ngw.id
  }
    route {
    cidr_block = aws_subnet.priv2_subnet.cidr_block
    gateway_id = aws_nat_gateway.ngw.id
  }
  tags = {
    Name = "tf-ngw-rt"
  }
}
resource "aws_route_table_association" "pri_subnet_ngw_ass" {
  subnet_id      = aws_subnet.priv_subnet.id
  route_table_id = aws_route_table.ngw_rt.id
}
resource "aws_route_table_association" "pri2_subnet_ngw_ass" {
  subnet_id      = aws_subnet.priv2_subnet.id
  route_table_id = aws_route_table.ngw_rt.id
}
# Create EC2
resource "aws_instance" "tf_demo" {
  ami           = "ami-0b5eea76982371e91"
  key_name =  "marco-keypair"
  subnet_id     = aws_subnet.pub_subnet.id
  vpc_security_group_ids = [aws_security_group.ssh_https_sg.id]
  instance_type = "t2.micro"
  tags = {
    Name = "tf-instance"
  }
}
# Create  rds Subnet group
resource "aws_db_subnet_group" "rds_subnet_grp" {
  name       = "rds-subgrp"
  subnet_ids = [aws_subnet.priv_subnet.id, aws_subnet.priv2_subnet.id]
  tags = {
    Name = "tf DB subnet group"
  }
}
# Create RDS
resource "aws_db_instance" "tf_db" {
  allocated_storage    = 10
  db_name              = "mydb"
#  subnet_id            = aws_subnet.priv_subnet.id
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.micro"
  username             = "admin"
  password             = "6886"
  parameter_group_name = "default.mysql5.7"
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_grp.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot  = true
}