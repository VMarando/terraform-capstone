resource "aws_instance" "web" {
  ami                    = "ami-0c02fb55956c7d316"
  instance_type           = "t2.micro"
  key_name                = var.key_name
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = templatefile("${path.module}/scripts/user_data.sh.tpl", {
    bucket_name = var.bucket_name
  })

  tags = {
    Name = "VideoWebServer"
  }
}
