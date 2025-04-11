##############################################
# Variables
##############################################

variable "ami_id" {
  description = "Amazon Machine Image (AMI) ID for Ubuntu 22.04"
  type        = string
  default     = "ami-0e1bed4f06a3b463d"  # Ubuntu 22.04 LTS AMI for us-east-1
}

variable "aws_region" {
  default = "us-east-1"
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
    default     = "us-east-1a" 
}

variable "video_files" {
  description = "List of video file names to upload."
  type        = list(string)
  default     = ["video1.mp4", "video2.mp4", "video3.mp4", "video4.mp4"]
}

variable "client_name" {
  description = "A header line for the web server's HTML page"
  type        = string
  default     = "Insert Client Name Here" # Edit Client name on TF web app workspace variables
}

variable "ftp_user" {
  description = "Base FTP user name for AWS Transfer Family."
  type        = string
  default     = "myftpuser"
}

variable "ftp_password" {
  description = "FTP password for AWS Transfer Family user."
  type        = string
  default     = "myftppassword"
}