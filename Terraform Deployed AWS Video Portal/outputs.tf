##############################################
# Outputs
##############################################

output "nginx_public_ip" {
  description = "Public IP address of the Nginx web server."
  value       = aws_instance.web_server.public_ip
}

output "random_id" {
  value = random_id.common_id.hex
  description = "The unique random ID generated for tenant isolation"
}
