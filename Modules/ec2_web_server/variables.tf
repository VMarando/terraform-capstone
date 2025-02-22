variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "Type of EC2 instance"
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  description = "Amazon Machine Image (AMI) ID"
  type        = string
  default     = "ami-00258761fd9151afd"
}

variable "instance_name" {
  description = "EC2 instance name tag"
  type        = string
  default     = "Tomcat-Test-Server"
}
