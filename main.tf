terraform {
  backend "local" {
    path = "./terraform.tfstate"
  }
}

resource "local_file" "example" {
  filename = "config.txt"
  content  = "This file was created by Terraform!"
}
