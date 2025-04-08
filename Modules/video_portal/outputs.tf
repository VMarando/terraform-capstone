output "video_portal_url" {
  value = "http://${aws_instance.video_portal.public_ip}"
}
