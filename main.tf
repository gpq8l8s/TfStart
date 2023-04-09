provider "aws" {
  region = "us-east-1"
  # Don't expose your keys on public
  access_key = "my-access-key"
  secret_key = "my-secret-key"
}

# 1. Create VPC
## Keyword : terraform aws vpc
resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "production"
  }
}

# 2. Create Internet Gateway
## Keyword : terraform aws internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id

  # tags = {
  #   Name = "main"
  # }
}

# 3. Create Custom Route Table
## Keyword : terraform aws route table
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    # 0.0.0.0/0 allows all the IPs
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Prod"
  }
}

# 4. Create a Subnet
resource "aws_subnet" "subnet-1" {
  vpc_id = aws_vpc.prod-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "prod-subnet"
  }
}

# 5. Associate subnet with Route Table
## Keyword : terraform aws route table associate
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

# 6. Create Security group to Allow Port 22, 80, 443 
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow Web inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description      = "HTTPS"
    # port from and to hav eto be same
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    # Allow everyont to access to the site
    cidr_blocks      = ["0.0.0.0/0"]
    # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }
  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }
  egress {
    from_port        = 0
    to_port          = 0
    # -1 protocol means any protocols
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    # ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

# 7. Create a Network Interface With an IP in the Subnet That was Created in Step 4
## Keyword : terraform aws network interface
resource "aws_network_interface" "web-server-nic" {
  subnet_id       =  aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]

  # attachment {
  #   instance     = aws_instance.test.id
  #   device_index = 1
  # }
}

# 8. Assign an Elastic IP(eip) to the Network Interface Created in Step 7
## Terraform can handle when it's not written asynchrously, but elestic IP rely on Internet gateway
## So let terraform have gateway then epi, if not, error will be thrown
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [
    ## Should give whole object so no need to specify ID here
    aws_internet_gateway.gw
  ]
}
## Output will be printed automatically when applied
output "server_public_ip" {
  value = aws_eip.one.public_ip
}

# 9. Create Ubuntu Server and Install/Enable Apache2
resource "aws_instance" "web-server-instance" {
  ami = "ami-007855ac798b5175e"
  instance_type = "t2.micro"
  availability_zone = "us-east-1a"
  key_name = "main-key"

  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  # user_data = <<-EOF
  #             #!/bin/bash
  #             sudo apt update -y
  #             sudo apt install apache2 -y
  #             sudo systemctl start apache2
  #             sudo bash -c 'echo web server running > /var/www/html/index.html'
  #             EOF
# Try If it doesn't work 
  user_data = <<-EOF
  #! /bin/bash
  sudo apt-get update
  sudo apt-get install -y apache2
  sudo systemctl start apache2
  sudo systemctl enable apache2
  echo "The page was created by the user data" | sudo tee /var/www/html/index.html
  EOF
  tags = {
    Name = "web-server"
  }
}

output "server_private_ip" {
  value = aws_instance.web-server-instance.private_ip
}
output "server_id" {
  value = aws_instance.web-server-instance.id
}