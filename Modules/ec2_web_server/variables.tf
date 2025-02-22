variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "Type of EC2 instance"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "Amazon Machine Image (AMI) ID for Ubuntu 24.04"
  type        = string
  default     = "ami-04b4f1a9cf54c11d0"  # Replace with latest AMI if needed
}

variable "instance_name" {
  description = "EC2 instance name tag"
  type        = string
  default     = "Tomcat-Test-Server"
}
