resource "aws_instance" "web" {
  ami                    = "ami-0c02fb55956c7d316"
  instance_type          = "t2.micro"
  key_name               = var.key_name
  subnet_id             = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  # 🚀 User Data Script: Installs Nginx & Configures the Server
  user_data = <<-EOF
#!/bin/bash
set -ex  

# Define log file
LOGFILE="/var/log/user-data.log"
exec > >(tee -a $LOGFILE) 2>&1  

echo "📌 Starting instance setup at $(date)"

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
sudo ufw --force enable  

# Add a simple test homepage
cat <<HTML_EOF | sudo tee /var/www/html/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Terraform Deployed Web Server</title>
</head>
<body>
    <h1>Welcome to Nginx on Ubuntu 22.04!</h1>
    <p>Optimus Capstone - Terraform Deployed AWS Web Server</p>
    <p>Region: \$(curl -s http://169.254.169.254/latest/meta-data/placement/region)</p>
    <p>Instance ID: \$(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>
</body>
</html>
HTML_EOF

# ✅ Reboot to ensure changes take effect
sudo reboot
EOF

  tags = {
    Name        = var.instance_name
    Environment = "Production"
    DeployedBy  = "Terraform"
  }
}
