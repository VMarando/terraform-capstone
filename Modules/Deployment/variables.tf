########################################
# Variables
########################################

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_profile" {
  type    = string
  default = "default"
}

variable "schedule_expression" {
  type    = string
  default = "rate(1 hour)" 
}

variable "ftp_host" {
  type    = string
  default = "ftp.example.com"
}

variable "ftp_user" {
  type    = string
  default = "my_ftp_user"
}

variable "ftp_password" {
  type    = string
  default = "my_ftp_password"
}
