resource "aws_security_group" "web_sg" {
  name        = "web-portal-sg"
  description = "Allow web traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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

resource "aws_instance" "web" {
  ami                    = "ami-0c02fb55956c7d316"
  instance_type           = "t2.micro"
  key_name                = var.key_name
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    sudo amazon-linux-extras install nginx1 -y
    systemctl enable nginx
    systemctl start nginx

    # Use double dollar signs to escape Terraform interpolation
    BUCKET_URL="https://$${var.bucket_name}.s3.amazonaws.com"
    VIDEO_FILES=("video1.mp4" "video2.mp4" "video3.mp4" "video4.mp4")

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

  tags = {
    Name = "VideoWebServer"
  }
}
