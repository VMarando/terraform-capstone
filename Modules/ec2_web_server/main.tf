# 🔑 Generate a New Key Pair (Saves .pem file locally)
resource "tls_private_key" "new_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "deployer" {
  key_name   = "my-nginx-key"
  public_key = tls_private_key.new_key.public_key_openssh
}

resource "local_file" "private_key" {
  content  = tls_private_key.new_key.private_key_pem
  filename = "${path.module}/my-nginx-key.pem"
  file_permission = "0600"
}

# 🚀 Create a Security Group for the Instance
resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Allow web and SSH traffic"

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

  # Allow all outbound traffic (VERY IMPORTANT)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 🖥 Create EC2 Instance with Nginx
resource "aws_instance" "web_server" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-EOF
            #!/bin/bash
            sudo apt update -y
            sudo apt install -y nginx

            # Start and enable Nginx
            sudo systemctl start nginx
            sudo systemctl enable nginx

            # Allow firewall access
            sudo ufw allow 80/tcp
            sudo ufw enable

            # Add a simple test homepage
            echo -e "<h1>Welcome to Nginx on Ubuntu 24.04!</h1>\n<p>Optimus Terraform Capstone - Our First Web Server</p>" | sudo tee /var/www/html/index.html
            EOF

  tags = {
    Name = var.instance_name
  }
}
