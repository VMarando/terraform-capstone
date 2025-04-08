output "video_portal_url" {
  value = "http://${module.video_portal.web.public_ip}"
}
