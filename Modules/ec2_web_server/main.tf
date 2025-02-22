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
  description = "Allow web, SSH, and HTTPS traffic"

  # Allow SSH (port 22) for EC2 Instance Connect
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

  # Allow HTTPS (port 443)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 🖥 Create EC2 Instance with Nginx
resource "aws_instance" "web_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  associate_public_ip_address = true  # ✅ Ensures EC2 gets a Public IP

  user_data = <<-EOF
#!/bin/bash
set -ex  # ✅ Debugging enabled to catch errors

# Update system packages
sudo apt update -y

# Install Nginx, AWS CLI, and EC2 Instance Connect
sudo apt install -y nginx awscli ec2-instance-connect

# Start and enable Nginx
sudo systemctl start nginx
sudo systemctl enable nginx

# Restart SSH for EC2 Instance Connect
sudo systemctl restart ssh

# Allow firewall access
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable  # ✅ Ensure UFW is active

# Add a simple test homepage
cat <<HTML_EOF | sudo tee /var/www/html/index.html
<h1>Welcome to Nginx on Ubuntu 24.04!</h1>
<p>Optimus Terraform Capstone - Our AWS First Web Server</p>
HTML_EOF

# ✅ Reboot to ensure changes take effect
sudo reboot
EOF

  tags = {
    Name = var.instance_name
  }
}
