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

  vpc_security_group_ids = [aws_security_group.web_sg.id]
}

resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Allow web and SSH traffic"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Open HTTP access
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Open SSH (can be restricted)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  # Allow all outbound traffic
  }
}
