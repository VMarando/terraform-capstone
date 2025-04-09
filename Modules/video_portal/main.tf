##############################################
# Resources and Infrastructure Configuration
##############################################

# 🔑 Generate a New SSH Key Pair (Saves .pem file locally)
resource "tls_private_key" "new_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate a random string to ensure a unique key pair name
resource "random_id" "key_id" {
  byte_length = 8
}

# Generate a random string to ensure a unique bucket name
resource "random_id" "bucket_id" {
  byte_length = 8
}

# Create an AWS key pair using our generated SSH key
resource "aws_key_pair" "deployer" {
  key_name   = "my-nginx-key-${random_id.key_id.hex}"
  public_key = tls_private_key.new_key.public_key_openssh
}

# Save the private key to a local file
resource "local_file" "private_key" {
  content         = tls_private_key.new_key.private_key_pem
  filename        = "${path.module}/my-nginx-key-${random_id.key_id.hex}.pem"
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
  map_public_ip_on_launch = true
  availability_zone       = var.availability_zone

  tags = {
    Name = "Public-Subnet"
  }
}

# 🚦 Create a Route Table and Associate with the Public Subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

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

# 🔒 Create a Security Group for the EC2 Instances
resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Allow web, SSH, and HTTPS traffic"
  vpc_id      = aws_vpc.main_vpc.id

  # Allow SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS
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

# 🖥 Deploy EC2 Instance with Nginx (Web Server)
resource "aws_instance" "web_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  subnet_id              = aws_subnet.public_subnet.id
  associate_public_ip_address = true

  # Install Nginx, AWS CLI, etc.
  user_data = <<-EOF
    #!/bin/bash
    set -ex

    LOGFILE="/var/log/user-data.log"
    exec > >(tee -a $LOGFILE) 2>&1

    echo "Starting Nginx web server setup at $(date)"

    sudo apt update -y
    sudo apt install -y nginx awscli ec2-instance-connect

    sudo systemctl start nginx
    sudo systemctl enable nginx
    sudo systemctl restart ssh

    sudo ufw allow 22/tcp
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw --force enable

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
      <p>Region: $(curl -s http://169.254.169.254/latest/meta-data/placement/region)</p>
      <p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>
    </body>
    </html>
    HTML_EOF

    sudo reboot
  EOF

  tags = {
    Name        = var.instance_name
    Environment = "Production"
    DeployedBy  = "Terraform"
  }
}

# 🖥 Deploy EC2 Instance for FTP-to-S3 Sync (Sync Server)
resource "aws_instance" "ftp_s3_sync_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  subnet_id              = aws_subnet.public_subnet.id
  associate_public_ip_address = true

  # Installs AWS CLI, FTP client, cron; sets up the FTP-to-S3 sync script
  user_data = <<-EOF
    #!/bin/bash
    set -ex

    # Install dependencies
    sudo apt-get update -y
    sudo apt-get install -y awscli ftp cron

    # Create a directory for video files
    mkdir -p /tmp/video_files

    # Create the FTP-to-S3 sync script
    cat <<'EOL' > /tmp/ftp_to_s3_sync.sh
    #!/bin/bash

    # FTP Server Credentials - update these with your actual FTP details
    FTP_HOST="ftp.example.com"
    FTP_USER="your_ftp_user"
    FTP_PASS="your_ftp_password"

    # Local directory to store downloaded files
    LOCAL_DIR="/tmp/video_files"

    # S3 bucket to upload files to
    S3_BUCKET="s3://your-bucket-name/"

    # Download files from the FTP server
    ftp -n $FTP_HOST <<END_SCRIPT
    quote USER $FTP_USER
    quote PASS $FTP_PASS
    mget /path/to/videos/* $LOCAL_DIR/
    quit
    END_SCRIPT

    # Sync the local directory with S3
    aws s3 sync $LOCAL_DIR $S3_BUCKET --acl public-read

    # Clean up local files after upload
    rm -rf $LOCAL_DIR
    EOL

    # Make the sync script executable
    chmod +x /tmp/ftp_to_s3_sync.sh

    # Set up a cron job to run the sync script every 5 minutes
    echo "*/5 * * * * /tmp/ftp_to_s3_sync.sh >> /var/log/ftp_to_s3_sync.log 2>&1" | sudo tee -a /etc/crontab

    # Restart cron
    sudo service cron restart
  EOF

  tags = {
    Name        = "FTP-to-S3-Sync-Server"
    Environment = "Production"
    DeployedBy  = "Terraform"
  }
}

# 🌐 Create an S3 Bucket (Randomly Named)
resource "aws_s3_bucket" "video_bucket" {
  bucket = "video-bucket-${random_id.bucket_id.hex}"

  tags = {
    Name = "Video Bucket"
  }
}

# 📄 Generate a Placeholder HTML page on the web server
#    (No local file upload resource is used, so we won't fail if no local videos exist)
resource "null_resource" "generate_html" {
  provisioner "local-exec" {
    command = <<-EOF
      # This script simply writes a placeholder HTML page
      # referencing the S3 bucket link. It won't list actual files unless
      # you update the logic to dynamically retrieve the object list.
      BUCKET_URL="https://$${aws_s3_bucket.video_bucket.bucket}.s3.amazonaws.com"

      echo "<html><body><h1>Client Video Footage</h1><p>No local videos are uploaded directly by Terraform.</p>" > /usr/share/nginx/html/index.html
      echo "<p>Videos will appear in $${BUCKET_URL} once the FTP-to-S3 sync job runs.</p>" >> /usr/share/nginx/html/index.html
      echo "</body></html>" >> /usr/share/nginx/html/index.html
    EOF
  }
}
