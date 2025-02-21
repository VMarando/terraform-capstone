resource "aws_instance" "web_server" {
  ami           = var.ami_id
  instance_type = var.instance_type

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y tomcat9 tomcat9-admin -y
              sudo systemctl start tomcat9
              sudo systemctl enable tomcat9
              echo "<h1>Tomcat Server is Running!</h1>" | sudo tee /var/lib/tomcat9/webapps/ROOT/index.html
              EOF

  tags = {
    Name = var.instance_name
  }

  security_groups = [aws_security_group.web_sg.name]
}

resource "aws_security_group" "web_sg" {
  name        = "web_sg"
  description = "Allow web and SSH traffic"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Open Tomcat HTTP access
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Open SSH (can be restricted)
  }
}
