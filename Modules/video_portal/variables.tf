##############################################
# Variables
##############################################

variable "ami_id" {
  description = "AMI to use for the EC2 instances."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t2.micro"
}

variable "instance_name" {
  description = "Name tag for the Nginx EC2 instance."
  type        = string
  default     = "MyNginxServer"
}

variable "availability_zone" {
  description = "The availability zone for the subnet."
  type        = string
}

variable "bucket_name" {
  description = "The name of the S3 bucket (if used externally)."
  type        = string
}

variable "video_files" {
  description = "List of video file names to upload."
  type        = list(string)
  default     = ["video1.mp4", "video2.mp4", "video3.mp4", "video4.mp4"]
}
