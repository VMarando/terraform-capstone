output "instance_public_ip" {
  description = "Public IP address of the Tomcat server"
  value       = aws_instance.web_server.public_ip
}
