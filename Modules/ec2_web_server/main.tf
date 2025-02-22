resource "aws_instance" "web_server" {
  ami           = var.ami_id
  instance_type = var.instance_type

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y tomcat9 tomcat9-admin -y
              sudo sed -i 's/port="8080"/port="80"/' /etc/tomcat9/server.xml
              sudo systemctl restart tomcat9
              sudo systemctl enable tomcat9
              echo "<h1>Tomcat Server is Running!</h1>" | sudo tee /var/lib/tomcat9/webapps/ROOT/index.html
              EOF

  tags = {
    Name = var.instance_name
  }

  # Associate the instance with the security group
  vpc_security_group_ids = [aws_security_group.web_sg.id]
}

resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Allow web and SSH traffic"

  # 🔒 Allow SSH access from anywhere (should be limited in production)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 🌐 Allow HTTP traffic on port 80 (for web access)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 🚀 Allow Tomcat traffic on port 8080 (optional, for direct Tomcat access)
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 🌍 Allow all outbound traffic (required for instance to reach the internet)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
