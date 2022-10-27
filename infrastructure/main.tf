variable "region" {
  default = "ap-southeast-1"
}
variable "prefix" {
  default = "nri"
}
variable "stage" {
  default = "demo"
}
variable "ssh_public" {
  default = "/home/gilbert/.ssh/zen.pub"
}


provider "aws" {
  region                   = var.region
  profile                  = "default"
  shared_config_files      = ["/home/gilbert/.aws/config"]
  shared_credentials_files = ["/home/gilbert/.aws/credentials"]
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = {
    Name      = "${var.prefix}-${var.stage}-vpc"
    Stage     = var.stage
    CreatedBy = "terraform"
  }
}

resource "aws_subnet" "public-a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"
  tags                    = {
    Name      = "${var.prefix}-${var.stage}-subnet-public-${var.region}a"
    Stage     = var.stage
    CreatedBy = "terraform"
  }
}
resource "aws_subnet" "public-b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}b"
  tags                    = {
    Name      = "${var.prefix}-${var.stage}-subnet-public-${var.region}b"
    Stage     = var.stage
    CreatedBy = "terraform"
  }
}
resource "aws_subnet" "private-a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/23"
  map_public_ip_on_launch = false
  availability_zone       = "${var.region}a"
  tags                    = {
    Name      = "${var.prefix}-${var.stage}-subnet-private-${var.region}a"
    Stage     = var.stage
    CreatedBy = "terraform"
  }
}
resource "aws_subnet" "private-b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.4.0/23"
  map_public_ip_on_launch = false
  availability_zone       = "${var.region}b"
  tags                    = {
    Name      = "${var.prefix}-${var.stage}-subnet-private-${var.region}b"
    Stage     = var.stage
    CreatedBy = "terraform"
  }
}


resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name      = "${var.prefix}-${var.stage}-internet-gateway"
    Stage     = var.stage
    CreatedBy = "terraform"
  }
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags   = {
    Name      = "${var.prefix}-${var.stage}-route-table-public"
    Stage     = var.stage
    CreatedBy = "terraform"
  }
}
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = {
    Name      = "${var.prefix}-${var.stage}-route-table-private"
    Stage     = var.stage
    CreatedBy = "terraform"
  }
}

resource "aws_route_table_association" "public-a" {
  subnet_id      = aws_subnet.public-a.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "public-b" {
  subnet_id      = aws_subnet.public-b.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "private-a" {
  subnet_id      = aws_subnet.private-a.id
  route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association" "private-b" {
  subnet_id      = aws_subnet.private-b.id
  route_table_id = aws_route_table.private.id
}


resource "aws_security_group" "backend" {
  name        = "${var.prefix}-${var.stage}-sg-backend"
  description = "Security group for Backend"
  vpc_id      = aws_vpc.main.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }
  ingress {
    from_port       = 80
    protocol        = "tcp"
    to_port         = 80
    cidr_blocks = [
      "0.0.0.0/0",
    ]
    description = "allow http connection from all"
  }
  tags = {
    Name      = "${var.prefix}-${var.stage}-sg-app"
    Stage     = var.stage
  }
}

resource "aws_security_group_rule" "ssh-to-backend" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = [
    "0.0.0.0/0",
  ]
  ipv6_cidr_blocks = [
    "::/0"
  ]
  description       = "allow ssh connection from all"
  security_group_id = aws_security_group.backend.id
}


resource "aws_security_group_rule" "https-to-backend" {
  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = [
    "0.0.0.0/0",
  ]
  ipv6_cidr_blocks = [
    "::/0"
  ]
  description       = "allow https connection from all"
  security_group_id = aws_security_group.backend.id
}


data "aws_ami" "amazon-linux-2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }

  owners = [
    "amazon"
  ]
}

resource "aws_key_pair" "ssh-key" {
  key_name   = "${var.prefix}-${var.stage}-backend-ssh-key"
  public_key = file(var.ssh_public)
}

resource "aws_instance" "backend" {
  ami = data.aws_ami.amazon-linux-2.id
  instance_type = "t3a.micro"
  subnet_id       = aws_subnet.public-a.id
  security_groups = [aws_security_group.backend.id]

  tags = {
    Name = "${var.prefix}-${var.stage}-backend"
  }

  key_name = aws_key_pair.ssh-key.key_name
}

resource "aws_eip" "eip_manager" {
  depends_on = [aws_instance.backend]
  instance = aws_instance.backend.id

  tags = {
    Name = "${var.prefix}-${var.stage}-eip-backend"
  }
}


