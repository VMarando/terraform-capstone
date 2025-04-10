########################################################
# main.tf: Deploy a Simple S3 Static Website
########################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Random suffix to ensure bucket name is globally unique
resource "random_id" "suffix" {
  byte_length = 4
}

# 1) S3 bucket (no 'acl' or 'website' blocks to avoid deprecation warnings)
resource "aws_s3_bucket" "site_bucket" {
  bucket = "${var.site_name}-${random_id.suffix.hex}"
}

# 2) Set a public-read ACL with a separate resource
resource "aws_s3_bucket_acl" "site_bucket_acl" {
  bucket = aws_s3_bucket.site_bucket.id
  acl    = "public-read"
}

# 3) Enable static website hosting
resource "aws_s3_bucket_website_configuration" "site_bucket_website" {
  bucket = aws_s3_bucket.site_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# 4) [Optional but recommended] Block Public Access must be disabled if you want a publicly accessible site
#    If your account or the bucket has "Block Public Access" turned on at a higher level,
#    you won't be able to apply a public ACL/policy. This resource lets you explicitly disable it *at the bucket level*.
resource "aws_s3_bucket_public_access_block" "public_off" {
  bucket = aws_s3_bucket.site_bucket.id

  block_public_acls   = false
  block_public_policy = false
  ignore_public_acls  = false
  restrict_public_buckets = false
}

# 5) [Optional] Bucket policy that grants public read of all objects
#    You can do this or rely on the object ACLs. This is generally safer than ACL = "public-read" alone.
resource "aws_s3_bucket_policy" "site_policy" {
  bucket = aws_s3_bucket.site_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "PublicReadGetObject",
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = [
          "${aws_s3_bucket.site_bucket.arn}/*"
        ]
      }
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.public_off]
}

# 6) S3 Object for the homepage (index.html)
#    This uploads your local "index.html" to the bucket with a public ACL.
resource "aws_s3_bucket_object" "index_html" {
  bucket       = aws_s3_bucket.site_bucket.id
  key          = "index.html"
  source       = "${path.module}/index.html"  # local file in the same folder
  content_type = "text/html"

  # Let the bucket policy handle public read or set an ACL here:
  acl = "public-read"

  depends_on = [
    aws_s3_bucket_website_configuration.site_bucket_website,
    aws_s3_bucket_public_access_block.public_off
  ]
}

# 7) Output the static website endpoint
output "website_url" {
  description = "URL to access the static website"
  # The recommended new usage is 'website_domain', combined with "http://"
  value = "http://${aws_s3_bucket_website_configuration.site_bucket_website.website_domain}"
}
