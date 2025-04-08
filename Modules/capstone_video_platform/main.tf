resource "aws_instance" "video_portal" {
  ami           = "ami-0c02fb55956c7d316"
  instance_type = "t2.micro"
  key_name      = var.key_name
  subnet_id     = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.video_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y nginx aws-cli
              systemctl enable nginx
              systemctl start nginx

              echo "<html><body><h1>Welcome to the HAD Video Portal</h1>" > /usr/share/nginx/html/index.html
              echo "<p>This server hosts secure links to your video footage.</p>" >> /usr/share/nginx/html/index.html
              echo "<ul>" >> /usr/share/nginx/html/index.html
              echo "<li><a href='https://${var.bucket_name}.s3.amazonaws.com/camera1.mp4'>camera1.mp4</a></li>" >> /usr/share/nginx/html/index.html
              echo "<li><a href='https://${var.bucket_name}.s3.amazonaws.com/camera2.mp4'>camera2.mp4</a></li>" >> /usr/share/nginx/html/index.html
              echo "</ul></body></html>" >> /usr/share/nginx/html/index.html
              EOF

  tags = {
    Name = "CustomVideoPortal"
  }
}

resource "aws_security_group" "video_sg" {
  name        = "video-portal-sg"
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
