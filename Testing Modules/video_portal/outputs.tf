##############################################
# Outputs
##############################################

output "nginx_public_ip" {
  description = "Public IP address of the Nginx web server."
  value       = aws_instance.web_server.public_ip
}

output "ftp_s3_sync_server_public_ip" {
  description = "Public IP address of the FTP-to-S3 sync server."
  value       = aws_instance.ftp_s3_sync_server.public_ip
}

output "random_id" {
  value = random_id.common_id.hex
  description = "The unique random ID generated for tenant isolation"
}
