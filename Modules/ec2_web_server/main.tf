provider "aws" {
  region = var.aws_region
}

# 🔑 Generate a New Key Pair (Downloads a .pem file)
resource "tls_private_key" "new_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "deployer" {
  key_name   = "my-tomcat-key"
  public_key = tls_private_key.new_key.public_key_openssh
}

resource "local_file" "private_key" {
  content  = tls_private_key.new_key.private_key_pem
  filename = "${path.module}/my-tomcat-key.pem"
  file_permission = "0600"
}

# 🚀 Create a Security Group for the Instance
resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Allow web, Tomcat, and SSH traffic"

  # Allow SSH (port 22)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP (port 80)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Tomcat (port 8080)
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic (VERY IMPORTANT)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 🖥 Create EC2 Instance with User Data to Install Tomcat
resource "aws_instance" "web_server" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer.key_name  # Attach the new key pair
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y tomcat9 tomcat9-admin -y
              sudo sed -i 's/port="8080"/port="80"/' /etc/tomcat9/server.xml
              sudo systemctl restart tomcat9
              sudo systemctl enable tomcat9
              echo "<h1>Tomcat Server is Running!</h1>" | sudo tee /var/lib/tomcat9/webapps/ROOT/index.html
              EOF

  tags = {
    Name = var.instance_name
  }
}

# 🎯 Output Public IP for Easy Access
output "instance_public_ip" {
  description = "Public IP of the Tomcat server"
  value       = aws_instance.web_server.public_ip
}
