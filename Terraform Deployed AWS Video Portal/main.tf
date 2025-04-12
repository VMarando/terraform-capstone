############################################################
# Terraform: Video Upload & Display Example (EC2-based, PRIVATE Bucket)
############################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

############################################################
# 1. Generate SSH Key Pair & Random ID
############################################################

resource "tls_private_key" "new_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "random_id" "common_id" {
  byte_length = 4
}

############################################################
# 2. AWS Key Pair and Local Private Key
############################################################

resource "aws_key_pair" "deployer" {
  key_name   = "my-nginx-key-${random_id.common_id.hex}"
  public_key = tls_private_key.new_key.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.new_key.private_key_pem
  filename        = "${path.module}/my-nginx-key-${random_id.common_id.hex}.pem"
  file_permission = "0600"
  depends_on      = [aws_key_pair.deployer]
}

############################################################
# 3. Networking: VPC, IGW, Subnet, Route Table
############################################################

resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Optimus-VPC-${random_id.common_id.hex}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "Main-IGW-${random_id.common_id.hex}"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = var.availability_zone
  tags = {
    Name = "Public-Subnet-${random_id.common_id.hex}"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "Public-RT-${random_id.common_id.hex}"
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

############################################################
# 4. Security Group: Allow SSH, HTTP, HTTPS
############################################################

resource "aws_security_group" "web_sg" {
  name        = "web_sg-${random_id.common_id.hex}"
  description = "Allow SSH (22), HTTP (80), and HTTPS (443)"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main_vpc.cidr_block]
  }

}

############################################################
# 5. Amazon EFS File System for Video Storage (Managed NAS)
############################################################

# Create an EFS file system for storing video files
resource "aws_efs_file_system" "video_efs" {
  creation_token   = "video-efs-${random_id.common_id.hex}"
  performance_mode = "generalPurpose"
  encrypted        = false

  tags = {
    Name = "VideoEFS-${random_id.common_id.hex}"
  }
}

# Create a mount target for the EFS in your public subnet(s)
resource "aws_efs_mount_target" "efs_mount" {
  file_system_id  = aws_efs_file_system.video_efs.id
  subnet_id       = aws_subnet.public_subnet.id
  security_groups = [aws_security_group.web_sg.id]
}

############################################################
# 6. EC2 Instance: Nginx Web Server (Dynamic File Listing)
############################################################

resource "aws_instance" "web_server" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.deployer.key_name
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  subnet_id                   = aws_subnet.public_subnet.id
  associate_public_ip_address = true

  depends_on = [
    aws_efs_file_system.video_efs  # Ensure EFS is created before mounting
  ]

  user_data = <<EOF
#!/bin/bash
set -ex

# Update and install required packages, including nfs-common for NFS mounts
sudo apt-get update -y
sudo apt-get install -y nginx awscli ec2-instance-connect openssl nfs-common

sudo systemctl start nginx
sudo systemctl enable nginx
sudo systemctl restart ssh

# (Optional) Configure UFW
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 2049/tcp  # Allow NFS
sudo ufw --force enable

# Generate self-signed certificate for HTTPS
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/nginx-selfsigned.key \
  -out /etc/ssl/certs/nginx-selfsigned.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=demo.local"

# Overwrite the default Nginx configuration with an HTTPS-enabled configuration
cat <<'NGINX_EOF' | sudo tee /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    root /var/www/html;
    index index.html;

    ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;

    # For the root URL, force serving index.html
    location = / {
        try_files /index.html =404;
    }

    # For all other requests, return 404 if not found
    location / {
        try_files $uri $uri/ =404;
    }
    }
NGINX_EOF

# Restart Nginx to apply the new HTTPS configuration
sudo systemctl restart nginx

# Create the mount point for EFS and mount the EFS file system
sudo mkdir -p /mnt/efs/videos

# Mount the EFS file system directly using interpolation
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_file_system.video_efs.id}.efs.${var.aws_region}.amazonaws.com:/ /mnt/efs/videos

# Add the mount to /etc/fstab for persistence using direct interpolation
echo "${aws_efs_file_system.video_efs.id}.efs.${var.aws_region}.amazonaws.com:/ /mnt/efs/videos nfs defaults 0 0" | sudo tee -a /etc/fstab

# Write out and run a dynamic index generation script using the EFS mount
cat <<'DYNAMIC_EOF' > /tmp/update_index.sh
#!/bin/bash
set -e

# Use the mounted EFS directory as the source for video files
LOCAL_DIR="/mnt/efs/videos"
TMP_HTML="/tmp/index.html"

# Ensure the videos directory exists
mkdir -p "$LOCAL_DIR"

# Begin generating the HTML
cat <<HTML_START > "$TMP_HTML"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>${var.client_name} - Video Library</title>
</head>
<body>
  <h1>${var.client_name} - Video Library</h1>
  <ul>
HTML_START

FILES=`ls -1 "$LOCAL_DIR"`
if [ -z "$FILES" ]; then
  echo "    <p>No videos available at this time.</p>" >> "$TMP_HTML"
else
  for object in $FILES; do
    echo "    <li><a href='/videos/$object'>$object</a></li>" >> "$TMP_HTML"
  done
fi

cat <<HTML_END >> "$TMP_HTML"
  </ul>
</body>
</html>
HTML_END

sudo mv "$TMP_HTML" /var/www/html/index.html
DYNAMIC_EOF

chmod +x /tmp/update_index.sh
sudo /tmp/update_index.sh # Run the script immediately

# Schedule the dynamic index update every 2 minutes
echo "*/2 * * * * root /tmp/update_index.sh >> /var/log/update_index_cron.log 2>&1" | sudo tee -a /etc/crontab
EOF

  tags = {
    Name        = "Nginx-WebServer-${random_id.common_id.hex}"
    Environment = "Production"
    DeployedBy  = "Terraform"
  }
}
