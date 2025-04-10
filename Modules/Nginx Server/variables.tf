variable "aws_region" {
  default = "us-east-1"
}

variable "site_name" {
  type    = string
  default = "my-site"
  description = "Used in the bucket name."
}
