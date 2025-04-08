terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "video_portal" {
  source           = "./modules/video_portal"
  vpc_id           = var.vpc_id
  public_subnet_id = var.public_subnet_id
  key_name         = var.key_name
  bucket_name      = var.bucket_name
}
