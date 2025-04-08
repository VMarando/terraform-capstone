variable "vpc_id" {}
variable "public_subnet_id" {}
variable "key_name" {}
variable "bucket_name" {
  description = "The name of the S3 bucket"
  type        = string
}

variable "web_sg_id" {
  description = "The ID of the web security group"
  type        = string
}
