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
  description = "Amazon Machine Image (AMI) ID for Ubuntu 22.04"
  type        = string
  default     = "ami-0e1bed4f06a3b463d"  # Ubuntu 22.04 LTS AMI for us-east-1
}


variable "instance_name" {
  description = "EC2 instance name tag"
  type        = string
  default     = "Nginx-Test-Server"
}

variable "availability_zone" {
  description = "The availability zone to launch resources in"
  type        = string
  default     = "us-east-1a"  # Replace with your preferred AZ
}