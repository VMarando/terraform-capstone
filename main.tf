module "video_portal" {
  source            = "./video_portal"
  bucket_name       = var.bucket_name
  key_name          = var.key_name
  public_subnet_id  = var.public_subnet_id
  vpc_id            = var.vpc_id
  web_sg_id         = var.web_sg_id
}

