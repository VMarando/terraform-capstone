resource "aws_instance" "web" {
  ami             = "ami-0c02fb55956c7d316"
  instance_type   = "t2.micro"
  key_name        = var.key_name
  subnet_id       = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-EOF
  #!/bin/bash
  yum update -y
  yum install -y nginx aws-cli
  systemctl enable nginx
  systemctl start nginx

  BUCKET_URL="https://\$\${var.bucket_name}.s3.amazonaws.com"
  # List of video files you want to display dynamically
  VIDEO_FILES=("video1.mp4" "video2.mp4" "video3.mp4" "video4.mp4")

  echo "<html><body><h1>Client Video Footage</h1><ul>" > /usr/share/nginx/html/index.html

  # Check if there are video files to display
  if [ \${#VIDEO_FILES[@]} -eq 0 ]; then
    echo "<p>No videos available at this time.</p>" >> /usr/share/nginx/html/index.html
  else
    # Loop through the array of videos and generate the <li> tags
    for video in "\${VIDEO_FILES[@]}"
    do
      echo "<li><a href='\${BUCKET_URL}/\$video'>\$video</a></li>" >> /usr/share/nginx/html/index.html
    done
  fi

  echo "</ul></body></html>" >> /usr/share/nginx/html/index.html
  EOF

  tags = {
    Name = "VideoWebServer"
  }
}

