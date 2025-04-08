variable "aws_region" {
  default = "us-east-1"
}

variable "vpc_id" {}
variable "public_subnet_id" {}
variable "key_name" {}
variable "bucket_name" {}

variable "web_sg_id" {
  description = "The ID of the security group"
  type        = string
}
