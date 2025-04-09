##############################################
# Terraform Configuration for Video Upload & Display
##############################################

# Generate an SSH key pair (stored as a local .pem file)
resource "tls_private_key" "new_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate a common random ID for naming all resources for tenant isolation
resource "random_id" "common_id" {
  byte_length = 8
}

##############################################
# AWS Key Pair and Local Private Key File
##############################################

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

##############################################
# Networking Resources: VPC, Internet Gateway, Subnet, and Route Table
##############################################

resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
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

##############################################
# Security Group: Allow SSH, HTTP, and HTTPS
##############################################

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
}

##############################################
# S3 Bucket for Video Storage
##############################################

resource "aws_s3_bucket" "video_bucket" {
  bucket = "video-bucket-${random_id.common_id.hex}"
  tags = {
    Name = "Video Bucket-${random_id.common_id.hex}"
  }
}

##############################################
# EC2 Instance: Nginx Web Server
##############################################

resource "aws_instance" "web_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  subnet_id              = aws_subnet.public_subnet.id
  associate_public_ip_address = true

  user_data = <<EOF
#!/bin/bash
set -ex

LOGFILE="/var/log/user-data.log"
exec > >(tee -a ${LOGFILE}) 2>&1

echo "Starting Nginx web server setup at $(date)"

# Install required packages
sudo apt update -y
sudo apt install -y nginx awscli ec2-instance-connect

sudo systemctl start nginx
sudo systemctl enable nginx
sudo systemctl restart ssh

sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# Create the update script to generate the index page dynamically
cat <<SCRIPT_EOF > /tmp/update_index.sh
#!/bin/bash
set -e
BUCKET_NAME="${aws_s3_bucket.video_bucket.bucket}"
WEB_ROOT="/var/www/html"
TMP_HTML="/tmp/index.html"

echo "<html><body><h1>${var.client_name} - Video Library</h1><ul>" > \$TMP_HTML
mapfile -t S3_FILES < <(aws s3 ls "s3://\$BUCKET_NAME" --recursive | awk '{print \$4}')
if [ \${#S3_FILES[@]} -eq 0 ]; then
  echo "<p>No videos available at this time.</p>" >> \$TMP_HTML
else
  for object in "\${S3_FILES[@]}"; do
    if [ -n "\$object" ]; then
      echo "<li><a href='https://\$BUCKET_NAME.s3.amazonaws.com/\$object'>\$object</a></li>" >> \$TMP_HTML
    fi
  done
fi
echo "</ul></body></html>" >> \$TMP_HTML
sudo mv \$TMP_HTML \$WEB_ROOT/index.html
SCRIPT_EOF

chmod +x /tmp/update_index.sh
# Run the update script immediately
/tmp/update_index.sh
# Set up a cron job to update the page every 5 minutes
echo "*/5 * * * * /tmp/update_index.sh >> /var/log/update_index_cron.log 2>&1" | sudo tee -a /etc/crontab
EOF

  tags = {
    Name        = "Nginx-WebServer-${random_id.common_id.hex}"
    Environment = "Production"
    DeployedBy  = "Terraform"
  }
}

##############################################
# EC2 Instance: FTP-to-S3 Sync Server
##############################################

resource "aws_instance" "ftp_s3_sync_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  subnet_id              = aws_subnet.public_subnet.id
  associate_public_ip_address = true

  user_data = <<EOF
#!/bin/bash
set -ex

sudo apt-get update -y
sudo apt-get install -y awscli ftp cron

mkdir -p /tmp/video_files

# Create the FTP-to-S3 sync script
cat <<SCRIPT_EOF > /tmp/ftp_to_s3_sync.sh
#!/bin/bash
# Update the following FTP values with your actual FTP server details
FTP_HOST="ftp.example.com"
FTP_USER="your_ftp_user"
FTP_PASS="your_ftp_password"
LOCAL_DIR="/tmp/video_files"
S3_BUCKET="s3://${aws_s3_bucket.video_bucket.bucket}"

ftp -n \$FTP_HOST <<END_SCRIPT
quote USER \$FTP_USER
quote PASS \$FTP_PASS
mget /path/to/videos/* \$LOCAL_DIR/
quit
END_SCRIPT

aws s3 sync \$LOCAL_DIR \$S3_BUCKET --acl public-read
rm -rf \$LOCAL_DIR
SCRIPT_EOF

chmod +x /tmp/ftp_to_s3_sync.sh
# Set up a cron job to run the FTP sync script every 5 minutes
echo "*/5 * * * * /tmp/ftp_to_s3_sync.sh >> /var/log/ftp_to_s3_sync.log 2>&1" | sudo tee -a /etc/crontab
sudo service cron restart
EOF

  tags = {
    Name        = "FTP-to-S3-Sync-${random_id.common_id.hex}"
    Environment = "Production"
    DeployedBy  = "Terraform"
  }
}
