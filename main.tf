module "video_portal" {
  source          = "./Modules/video_portal"
  vpc_id          = var.vpc_id
  public_subnet_id = var.public_subnet_id
  key_name        = var.key_name
  bucket_name     = var.bucket_name
  web_sg_id       = var.web_sg_id
}

provider "aws" {
  region = "us-east-1"  # Replace with your desired AWS region
}