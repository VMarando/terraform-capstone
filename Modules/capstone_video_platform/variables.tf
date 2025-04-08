variable "aws_region" {
  default = "us-east-1"
}

variable "vpc_id" {
  description = "The ID of the VPC where resources are deployed"
}

variable "public_subnet_id" {
  description = "The public subnet ID to launch the EC2 instance into"
}

variable "key_name" {
  description = "The SSH key name for EC2"
}

variable "bucket_name" {
  description = "The S3 bucket where videos are stored"
}
