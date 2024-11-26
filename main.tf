terraform{
    required_providers {
      aws                   = {
        source              = "hashicorp/aws"
        version             = "~> 5.0"
      }
    }
    required_version        = "= 1.9.8"
}

# Define the locals variables for the root module
locals {
  key_name                  = "wordpress_sql"
  private_key_path          = "./wordpress_sql.pem"
}

# Create a vpc
resource "aws_vpc" "my_vpc" {
  cidr_block                = "10.0.0.0/16"
  instance_tenancy          = "default"

  tags                      = {
    Name                    = "my_vpc"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id                    = aws_vpc.my_vpc.id

  tags                      = {
    Name                    = "my_igw"
  }
}

# Create a public subnet
resource "aws_subnet" "my_public_subnet" {
  vpc_id                    = aws_vpc.my_vpc.id
  cidr_block                = "10.0.1.0/24"
  map_public_ip_on_launch   = true

  tags                      = {
    Name                    = "my_public_subnet"
  }
}

# Create an Elastic IP
resource "aws_eip" "eip_for_database" {
  domain                    = "vpc"
}

# Create a nat gateway
resource "aws_nat_gateway" "nat_gateway_for_database" {
  allocation_id             = aws_eip.eip_for_database.id
  subnet_id                 = aws_subnet.my_public_subnet.id

  tags                      = {
    name                    = "nat_gateway_for_database"
  }

  depends_on = [ aws_internet_gateway.my_igw ]
}

# Create a public route table for the public subnet
resource "aws_route_table" "my_public_route_table" {
  vpc_id                    = aws_vpc.my_vpc.id

  route {
    cidr_block              = "0.0.0.0/0"
    gateway_id              = aws_internet_gateway.my_igw.id
  }

  tags                      = {
    Name                    = "my_public_route_table"
  }
}

# Associate the public route table to the public subnet
resource "aws_route_table_association" "public_rt_association" {
  subnet_id                 = aws_subnet.my_public_subnet.id
  route_table_id            = aws_route_table.my_public_route_table.id
}

# Create a private subnet
resource "aws_subnet" "my_private_subnet" {
  vpc_id                    = aws_vpc.my_vpc.id
  cidr_block                = "10.0.2.0/24"

  tags                      = {
    Name                    = "my_private_subnet"
  }
}

# Create a private route table for the private subnet
resource "aws_route_table" "my_private_route_table" {
  vpc_id                    = aws_vpc.my_vpc.id

  route {
    cidr_block              = "0.0.0.0/0"
    nat_gateway_id          = aws_nat_gateway.nat_gateway_for_database.id
  }

  tags                      = {
    Name                    = "my_private_route_table"
  }
}

# Associate the public route table to the public subnet
resource "aws_route_table_association" "private_rt_association" {
  subnet_id                 = aws_subnet.my_private_subnet.id
  route_table_id            = aws_route_table.my_private_route_table.id
}

# Create a security group for wordpress
resource "aws_security_group" "my_security_group_for_wordpress" {
  name                      = "my_security_group_for_wordpress"
  description               = "Access to wordpress"
  vpc_id                    = aws_vpc.my_vpc.id

  # Create a security group ingress rule http from the internet ipv4
  ingress {
    from_port               = 80
    protocol                = "tcp"
    to_port                 = 80
    cidr_blocks             = ["0.0.0.0/0"]
  }

  ingress {
    from_port               = 443
    protocol                = "tcp"
    to_port                 = 443
    cidr_blocks             = ["0.0.0.0/0"]
  }

  # Allow ssh access
  ingress {
    from_port               = 22
    protocol                = "tcp"
    to_port                 = 22
    cidr_blocks             = ["0.0.0.0/0"]
  }

  # Allow MySQL access to the database (port 3306)
  ingress {
    from_port               = 3306
    protocol                = "tcp"
    to_port                 = 3306
    security_groups         = [aws_security_group.my_security_group_for_db.id]
  }

  # Allow all outbound traffic for internet access
  egress {
    from_port               = 0
    to_port                 = 0
    protocol                = "-1"
    cidr_blocks             = ["0.0.0.0/0"]
  }

  tags                      = {
    Name                    = "my_security_group_for_wordpress"
  }
}

# Create an ingress security group rule for port 3306
resource "aws_security_group_rule" "ingress_security_group_rule_for_port_3306" {
  type                      = "ingress"
  from_port                 = 3306
  to_port                   = 3306
  protocol                  = "tcp"
  cidr_blocks               = [aws_subnet.my_private_subnet.cidr_block]
  security_group_id         = aws_security_group.my_security_group_for_db.id
}

# Create a security group for database
resource "aws_security_group" "my_security_group_for_db" {
  name                      = "my_security_group_for_db"
  description               = "Access to db"
  vpc_id                    = aws_vpc.my_vpc.id

  # Allow ssh access
  ingress {
    from_port               = 22
    protocol                = "tcp"
    to_port                 = 22
    cidr_blocks             = ["0.0.0.0/0"]
  }

  egress {
    from_port               = 0
    to_port                 = 0
    protocol                = "-1"
    cidr_blocks             = ["0.0.0.0/0"]
  }

  tags                      = {
    Name                    = "my_security_group_for_db"
  }
}

# Create an instance (wordpress) in the public subnet
resource "aws_instance" "wordpress_server" {
  ami                       = "ami-03ceeb33c1e4abcd1"
  instance_type             = "t2.micro"
  subnet_id                 = aws_subnet.my_public_subnet.id
  security_groups           = [aws_security_group.my_security_group_for_wordpress.id]
  key_name                  = local.key_name

  tags                      = {
    Name                    = "wordpress_server"
  }
}

# Create an instance (MySQL) in the private subnet
resource "aws_instance" "mysql_server" {
  ami                       = "ami-03ceeb33c1e4abcd1"
  instance_type             = "t2.micro"
  subnet_id                 = aws_subnet.my_private_subnet.id
  security_groups           = [aws_security_group.my_security_group_for_db.id]
  key_name                  = local.key_name

  tags                      = {
    Name                    = "mysql_server"
  }
}