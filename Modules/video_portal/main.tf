# 🔑 Generate a New SSH Key Pair (Saves .pem file locally)
resource "tls_private_key" "new_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate a random string to ensure unique key pair name
resource "random_id" "key_id" {
  byte_length = 8  # You can adjust the byte length for more or fewer characters
}

# Generate a random string to ensure unique bucket name
resource "random_id" "bucket_id" {
  byte_length = 8  # Adjust byte length for a unique bucket name
}

resource "aws_key_pair" "deployer" {
  key_name   = "my-nginx-key-${random_id.key_id.hex}"  # Combine static part with random string
  public_key = tls_private_key.new_key.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.new_key.private_key_pem
  filename        = "${path.module}/my-nginx-key-${random_id.key_id.hex}.pem"  # Save with a unique name
  file_permission = "0600"
  depends_on      = [aws_key_pair.deployer]
}

# 🌐 Create a VPC
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
  
  tags = {
    Name = "Optimus-VPC"
  }
}

# 📡 Create an Internet Gateway (Needed for Public Subnet)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "Main-IGW"
  }
}

# 📍 Create a Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true  # ✅ Ensures EC2 instances get public IPs
  availability_zone       = var.availability_zone

  tags = {
    Name = "Public-Subnet"
  }
}

# 🚦 Create a Route Table and Associate with the Public Subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  # 🔗 Route all outbound traffic (0.0.0.0/0) to the Internet Gateway
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Public-RT"
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# 🔒 Create a Security Group for the EC2 Instance
resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Allow web, SSH, and HTTPS traffic"
  vpc_id      = aws_vpc.main_vpc.id

  # 🟢 Allow SSH (port 22) for remote access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 🟢 Allow HTTP (port 80) for web traffic
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 🟢 Allow HTTPS (port 443) for secure traffic
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 🔴 Allow all outbound traffic (Needed for updates & installs)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 🖥 Deploy EC2 Instance for FTP-to-S3 Sync and Nginx
resource "aws_instance" "ftp_s3_sync_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  subnet_id              = aws_subnet.public_subnet.id
  associate_public_ip_address = true

  # 🚀 User Data Script: Installs dependencies and sets up cron job for FTP to S3 sync
  user_data = <<-EOF
#!/bin/bash
set -ex

# Install AWS CLI, FTP client, and cron
sudo apt-get update -y
sudo apt-get install -y awscli ftp cron

# Create a local directory for the video files
mkdir -p /tmp/video_files

# Create the FTP to S3 sync script
cat <<'EOL' > /tmp/ftp_to_s3_sync.sh
#!/bin/bash

# FTP Server Credentials
FTP_HOST="ftp.example.com"
FTP_USER="your_ftp_user"
FTP_PASS="your_ftp_password"

# Local directory to store downloaded files
LOCAL_DIR="/tmp/video_files"

# S3 bucket to upload files to
S3_BUCKET="s3://your-bucket-name/"

# Download the files from the FTP server
ftp -n $FTP_HOST <<END_SCRIPT
quote USER $FTP_USER
quote PASS $FTP_PASS
mget /path/to/videos/* $LOCAL_DIR/
quit
END_SCRIPT

# Upload the downloaded files to the S3 bucket
aws s3 sync $LOCAL_DIR $S3_BUCKET --acl public-read

# Clean up: Remove downloaded files after upload
rm -rf $LOCAL_DIR
EOL

# Make the script executable
chmod +x /tmp/ftp_to_s3_sync.sh

# Set up cron job to run the script every 5 minutes
echo "*/5 * * * * /tmp/ftp_to_s3_sync.sh >> /var/log/ftp_to_s3_sync.log 2>&1" | sudo tee -a /etc/crontab

# Restart cron service to apply the changes
sudo service cron restart
EOF

  tags = {
    Name        = "FTP-to-S3-Sync-Server"
    Environment = "Production"
    DeployedBy  = "Terraform"
  }
}

# 🌐 Create an S3 Bucket for video storage with a random name
resource "aws_s3_bucket" "video_bucket" {
  bucket = "video-bucket-${random_id.bucket_id.hex}"  # Combine static part with random string

  tags = {
    Name = "Video Bucket"
  }
}

# 📤 Upload video files to the S3 bucket
resource "aws_s3_object" "video_files" {
  count   = length(var.video_files)
  bucket  = aws_s3_bucket.video_bucket.bucket
  key     = element(var.video_files, count.index)
  source  = "path_to_video_files/${element(var.video_files, count.index)}"
  acl     = "public-read"
}

# 📄 Bash script to create the HTML file for the Nginx server
resource "null_resource" "generate_html" {
  provisioner "local-exec" {
    command = <<-EOF
      BUCKET_URL="https://$${aws_s3_bucket.video_bucket.bucket}.s3.amazonaws.com"
      VIDEO_FILES=(${join(" ", var.video_files)})

      echo "<html><body><h1>Client Video Footage</h1><ul>" > /usr/share/nginx/html/index.html

      if [ $${#VIDEO_FILES[@]} -eq 0 ]; then
        echo "<p>No videos available at this time.</p>" >> /usr/share/nginx/html/index.html
      else
        for video in "$${VIDEO_FILES[@]}"
        do
          echo "<li><a href='$${BUCKET_URL}/$video'>$video</a></li>" >> /usr/share/nginx/html/index.html
        done
      fi

      echo "</ul></body></html>" >> /usr/share/nginx/html/index.html
    EOF
  }
}

# Output the public IP of the NGINX instance for easy access
output "nginx_public_ip" {
  value = aws_instance.web_server.public_ip
}

# Output the public IP of the FTP-to-S3 Sync EC2 instance for easy access
output "ftp_s3_sync_server_public_ip" {
  value = aws_instance.ftp_s3_sync_server.public_ip
}

# Define variables for bucket name and video files
variable "bucket_name" {
  description = "The name of the S3 bucket"
  type        = string
