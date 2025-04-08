module "video_portal" {
  source = "./Modules/video_portal"
  
  key_name          = "your-key-name"
  public_subnet_id  = "your-subnet-id"
  bucket_name       = "your-bucket-name"
}

output "video_portal_url" {
  value = "http://${module.video_portal.web.public_ip}"
}
