##########################################################
# main.tf
##########################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.0.0"
}

# AWS Provider
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# Random suffix for uniqueness
resource "random_id" "suffix" {
  byte_length = 4
}

#############################################
# 1. S3 Bucket for Videos
#############################################

resource "aws_s3_bucket" "videos" {
  bucket = "videos-${random_id.suffix.hex}" 
  # Omit 'acl' and 'website' block to avoid deprecation warnings
}

# Separate ACL resource to set 'public-read' if you want a public website
resource "aws_s3_bucket_acl" "videos_acl" {
  bucket = aws_s3_bucket.videos.id
  acl    = "public-read"
}

# Configure static website hosting
resource "aws_s3_bucket_website_configuration" "videos_website" {
  bucket = aws_s3_bucket.videos.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# Allow public GET access to the objects
resource "aws_s3_bucket_public_access_block" "videos_access_block" {
  bucket = aws_s3_bucket.videos.id
  block_public_acls   = false
  block_public_policy = false
  ignore_public_acls  = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "videos_policy" {
  bucket = aws_s3_bucket.videos.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.videos.arn}/*"
      }
    ]
  })
}

#############################################
# 2. Lambda IAM Role & Policy
#############################################

resource "aws_iam_role" "lambda_exec" {
  name = "ftp-sync-lambda-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action   = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_exec_policy" {
  name = "ftp-sync-lambda-policy-${random_id.suffix.hex}"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # CloudWatch logs
      {
        Effect   = "Allow",
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      # S3 access to our specific bucket
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetObject"
        ],
        Resource = [
          aws_s3_bucket.videos.arn,
          "${aws_s3_bucket.videos.arn}/*"
        ]
      }
    ]
  })
}

#############################################
# 3. Lambda Function & Archive
#############################################

# Archive the local folder with your Python code, e.g. 'lambda_code'
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_code"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "ftp_sync" {
  function_name = "ftp-sync-${random_id.suffix.hex}"
  runtime       = "python3.9"
  handler       = "lambda_function.lambda_handler"
  role          = aws_iam_role.lambda_exec.arn

  filename            = data.archive_file.lambda_zip.output_path
  source_code_hash    = data.archive_file.lambda_zip.output_base64sha256
  publish             = true
  timeout             = 300
  memory_size         = 512

  environment {
    variables = {
      FTP_HOST    = var.ftp_host
      FTP_USER    = var.ftp_user
      FTP_PASS    = var.ftp_password
      BUCKET_NAME = aws_s3_bucket.videos.bucket
    }
  }
}

#############################################
# 4. EventBridge (CloudWatch) Schedule
#############################################

resource "aws_cloudwatch_event_rule" "ftp_sync_rule" {
  name                = "ftp-sync-schedule-${random_id.suffix.hex}"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "ftp_sync_target" {
  rule      = aws_cloudwatch_event_rule.ftp_sync_rule.name
  target_id = "ftp-sync-lambda-target"
  arn       = aws_lambda_function.ftp_sync.arn
}

resource "aws_lambda_permission" "allow_eventbridge_invoke" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ftp_sync.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ftp_sync_rule.arn
}

#############################################
# 5. Example: Upload a Placeholder index.html
#############################################

resource "null_resource" "upload_index" {
  provisioner "local-exec" {
    command = <<EOC
echo "<html><body><h1>Placeholder Index</h1><p>No videos yet. Lambda will upload them soon.</p></body></html>" > index.html
aws s3 cp index.html s3://${aws_s3_bucket.videos.bucket}/index.html --acl public-read --profile ${var.aws_profile} --region ${var.aws_region}
rm -f index.html
EOC
  }
  depends_on = [
    aws_s3_bucket.videos,
    aws_s3_bucket_acl.videos_acl,
    aws_s3_bucket_website_configuration.videos_website
  ]
}

#############################################
# 6. Output: Website Domain
#############################################
output "s3_website_url" {
  description = "HTTP endpoint for the S3 static site"
  value       = "http://${aws_s3_bucket_website_configuration.videos_website.website_domain}"
}
