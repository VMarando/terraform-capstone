module "video_portal" {
  source = "./Modules/video_portal"  # Adjust to the correct path if necessary

  # Pass the required variables
  web_sg_id = aws_security_group.web_sg.id   # Assuming web_sg is created in the parent configuration
  vpc_id    = var.vpc_id                     # This should be defined in your variables.tf or elsewhere
}


