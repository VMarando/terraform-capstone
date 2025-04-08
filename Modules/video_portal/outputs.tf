output "video_portal_url" {
  value = "http://${module.video_portal.web.public_ip}"
}

output "video_portal_s3_bucket" {
  value = "${aws_s3_bucket.video_bucket.bucket}"
}

output "web_security_group_id" {
  value = "${aws_security_group.web_sg.id}"
}
