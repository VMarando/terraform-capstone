output "instance_public_ip" {
  description = "Public IP of the Nginx web server"
  value       = aws_instance.web_server.public_ip
}
