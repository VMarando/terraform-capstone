############################################################
# Terraform: Video Upload & Display Example (EC2-based)
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
  # region is implied; either set AWS_REGION env, or define a var here
}

############################################################
# 1. Generate SSH Key Pair & Random ID
############################################################
resource "tls_private_key" "new_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "random_id" "common_id" {
  byte_length = 8
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
}

############################################################
# 5. S3 Bucket for Video Storage
############################################################
resource "aws_s3_bucket" "video_bucket" {
  bucket = "video-bucket-${random_id.common_id.hex}"
  tags = {
    Name = "Video Bucket-${random_id.common_id.hex}"
  }
}

# If you want the videos publicly readable, do a separate ACL or policy:
resource "aws_s3_bucket_acl" "public_acl" {
  bucket = aws_s3_bucket.video_bucket.id
  acl    = "public-read"
}

# If your account blocks public access, you must turn it off at bucket level:
resource "aws_s3_bucket_public_access_block" "pab" {
  bucket = aws_s3_bucket.video_bucket.id

  block_public_acls   = false
  block_public_policy = false
  ignore_public_acls  = false
  restrict_public_buckets = false
}

# A bucket policy allowing public read (optional but often recommended):
resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.video_bucket.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "PublicReadGetObject",
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.video_bucket.arn}/*"
      }
    ]
  })
  depends_on = [
    aws_s3_bucket_public_access_block.pab
  ]
}

############################################################
# 6. IAM Role & Instance Profile (For EC2 -> S3 Access)
############################################################
resource "aws_iam_role" "ec2_role" {
  name = "ec2_video_role-${random_id.common_id.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_s3_policy" {
  name = "ec2_s3_policy-${random_id.common_id.hex}"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowS3ListAndGet",
        Effect = "Allow",
        Action = [
          "s3:ListBucket",
          "s3:GetObject"
        ],
        Resource = [
          aws_s3_bucket.video_bucket.arn,
          "${aws_s3_bucket.video_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_video_profile-${random_id.common_id.hex}"
  role = aws_iam_role.ec2_role.name
}

############################################################
# 7. EC2 Instance: Nginx Web Server (Dynamic Video List)
############################################################
resource "aws_instance" "web_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  subnet_id              = aws_subnet.public_subnet.id
  associate_public_ip_address = true
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  # Ensure IAM profile and S3 bucket exist before creating the instance
  depends_on = [
    aws_s3_bucket.video_bucket,
    aws_s3_bucket_policy.bucket_policy,
    aws_iam_instance_profile.ec2_profile
  ]

  user_data = <<EOF
#!/bin/bash
set -ex

LOGFILE="/var/log/user-data.log"
exec > >(tee -a $${LOGFILE}) 2>&1

echo "Starting Nginx setup at $$(date)"

# Install Nginx, AWS CLI, and EC2 Instance Connect
sudo apt-get update -y
sudo apt-get install -y nginx awscli ec2-instance-connect

# Start services
sudo systemctl start nginx
sudo systemctl enable nginx
sudo systemctl restart ssh

# (Optional) UFW
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# Create a script to dynamically generate /var/www/html/index.html by listing S3
cat <<'SCRIPT_EOF' > /tmp/update_index.sh
#!/bin/bash
set -e

BUCKET_NAME="${aws_s3_bucket.video_bucket.bucket}"
WEB_ROOT="/var/www/html"
TMP_HTML="/tmp/index.html"
EC2_REGION=$$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

echo "<html><body><h1>${var.client_name} - Video Library</h1><ul>" > $${TMP_HTML}

# List objects in S3
FILES=$$(aws s3 ls "s3://$${BUCKET_NAME}" --region "$${EC2_REGION}" --recursive | awk '{print $$4}')

if [ -z "$$FILES" ]; then
  echo "<p>No videos available at this time.</p>" >> $${TMP_HTML}
else
  for object in $$FILES; do
    if [ -n "$${object}" ]; then
      echo "<li><a href='https://$${BUCKET_NAME}.s3.amazonaws.com/$${object}'>$${object}</a></li>" >> $${TMP_HTML}
    fi
  done
fi

echo "</ul></body></html>" >> $${TMP_HTML}
sudo mv $${TMP_HTML} $${WEB_ROOT}/index.html
SCRIPT_EOF

chmod +x /tmp/update_index.sh

# Run immediately
/tmp/update_index.sh

# Re-run every 5 minutes
echo "*/5 * * * * /tmp/update_index.sh >> /var/log/update_index_cron.log 2>&1" | sudo tee -a /etc/crontab

# Optionally reboot
# sudo reboot
EOF

  tags = {
    Name        = "Nginx-WebServer-${random_id.common_id.hex}"
    Environment = "Production"
    DeployedBy  = "Terraform"
  }
}

############################################################
# 8. EC2 Instance: FTP-to-S3 Sync Server
############################################################
resource "aws_instance" "ftp_s3_sync_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  subnet_id              = aws_subnet.public_subnet.id
  associate_public_ip_address = true

  # user_data script
  user_data = <<EOF
#!/bin/bash
set -ex

sudo apt-get update -y
sudo apt-get install -y awscli ftp cron

mkdir -p /tmp/video_files

cat <<'SCRIPT_EOF' > /tmp/ftp_to_s3_sync.sh
#!/bin/bash
set -e

FTP_HOST="ftp.example.com"
FTP_USER="your_ftp_user"
FTP_PASS="your_ftp_password"
LOCAL_DIR="/tmp/video_files"
S3_BUCKET="s3://${aws_s3_bucket.video_bucket.bucket}"
EC2_REGION=$$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Get from FTP
ftp -n $${FTP_HOST} <<END_SCRIPT
quote USER $${FTP_USER}
quote PASS $${FTP_PASS}
mget /path/to/videos/* $${LOCAL_DIR}/
quit
END_SCRIPT

# Sync to S3
aws s3 sync $${LOCAL_DIR} $${S3_BUCKET} --acl public-read --region $${EC2_REGION}
rm -rf $${LOCAL_DIR}
SCRIPT_EOF

chmod +x /tmp/ftp_to_s3_sync.sh

echo "*/5 * * * * /tmp/ftp_to_s3_sync.sh >> /var/log/ftp_to_s3_sync.log 2>&1" | sudo tee -a /etc/crontab
sudo service cron restart
EOF

  tags = {
    Name        = "FTP-to-S3-Sync-${random_id.common_id.hex}"
    Environment = "Production"
    DeployedBy  = "Terraform"
  }
}

