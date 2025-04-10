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
# 5. S3 Bucket for Video Storage (PRIVATE)
############################################################

resource "aws_s3_bucket" "video_bucket" {
  bucket = "video-bucket-${random_id.common_id.hex}"
  tags = {
    Name = "Video Bucket-${random_id.common_id.hex}"
  }
}

# (No public ACL or bucket policy, so the bucket remains private)

############################################################
# 6. IAM Role & Instance Profile (For EC2 -> S3 Access)
############################################################

resource "aws_iam_role" "ec2_role" {
  name = "ec2_video_role-${random_id.common_id.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ec2_s3_policy" {
  name = "ec2_s3_policy-${random_id.common_id.hex}"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid    = "AllowS3ListAndGet",
      Effect = "Allow",
      Action = [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject"  // needed for FTP sync to upload files
      ],
      Resource = [
        aws_s3_bucket.video_bucket.arn,
        "${aws_s3_bucket.video_bucket.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_video_profile-${random_id.common_id.hex}"
  role = aws_iam_role.ec2_role.name
}

############################################################
# 7. EC2 Instance: Nginx Web Server (Dynamic File Listing)
############################################################

resource "aws_instance" "web_server" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.deployer.key_name
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  subnet_id                   = aws_subnet.public_subnet.id
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name

  depends_on = [
    aws_s3_bucket.video_bucket,
    aws_iam_instance_profile.ec2_profile
  ]

  user_data = <<EOF
#!/bin/bash
set -ex

# Update and install required packages
sudo apt-get update -y
sudo apt-get install -y nginx awscli ec2-instance-connect

sudo systemctl start nginx
sudo systemctl enable nginx
sudo systemctl restart ssh

# (Optional) Configure UFW
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# Create the local directory for videos
sudo mkdir -p /var/www/html/videos

# Write out and run a dynamic index generation script
cat <<'DYNAMIC_EOF' > /tmp/update_index.sh
#!/bin/bash
set -e

LOCAL_DIR="/var/www/html/videos"
TMP_HTML="/tmp/index.html"

# Ensure the videos directory exists
mkdir -p "$LOCAL_DIR"

# Sync contents from the private S3 bucket into the local videos folder
aws s3 sync s3://${aws_s3_bucket.video_bucket.bucket} "$LOCAL_DIR" --region `curl -s http://169.254.169.254/latest/meta-data/placement/region`

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
if [ -z "\$FILES" ]; then
  echo "    <p>No videos available at this time.</p>" >> "$TMP_HTML"
else
  for object in \$FILES; do
    echo "    <li><a href='/videos/\$object'>\$object</a></li>" >> "$TMP_HTML"
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
# Run the script immediately
/tmp/update_index.sh

# Schedule the dynamic index update every 5 minutes
echo "*/5 * * * * /tmp/update_index.sh >> /var/log/update_index_cron.log 2>&1" | sudo tee -a /etc/crontab
EOF

  tags = {
    Name        = "Nginx-WebServer-${random_id.common_id.hex}"
    Environment = "Production"
    DeployedBy  = "Terraform"
  }
}

############################################################
# 8. AWS Transfer Family SFTP Server (Managed FTP Service)
############################################################

# IAM Role for Transfer Family
resource "aws_iam_role" "transfer_role" {
  name = "transfer_role-${random_id.common_id.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "transfer.amazonaws.com" }
    }]
  })
}

# IAM Policy for Transfer Family role to access S3 bucket (list, get, put)
resource "aws_iam_role_policy" "transfer_policy" {
  name = "transfer_policy-${random_id.common_id.hex}"
  role = aws_iam_role.transfer_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid: "AllowS3Access",
        Effect: "Allow",
        Action: [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject"
        ],
        Resource: [
          aws_s3_bucket.video_bucket.arn,
          "${aws_s3_bucket.video_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Create the AWS Transfer Family Server for SFTP
resource "aws_transfer_server" "sftp_server" {
  identity_provider_type = "SERVICE_MANAGED"  # AWS manages identity for this example
  endpoint_type          = "PUBLIC"
  protocols              = ["SFTP"]

  tags = {
    Name = "SFTP-Server-${random_id.common_id.hex}"
  }
}

# Create a Transfer Family User
resource "aws_transfer_user" "sftp_user" {
  server_id      = aws_transfer_server.sftp_server.id
  user_name      = "${var.ftp_user}-${random_id.common_id.hex}"
  role           = aws_iam_role.transfer_role.arn
  home_directory = "/${aws_s3_bucket.video_bucket.bucket}"
  
  tags = {
    Name = "SFTP-User-${random_id.common_id.hex}"
  }
}
