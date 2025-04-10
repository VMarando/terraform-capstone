###########################################
# Provider & Basic Setup
###########################################
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  # If using local state or workspaces, configure here
  # For example, if you're using Terraform Cloud, remove backend config or set it up as needed
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

###########################################
# Random Suffix for Uniqueness
###########################################
resource "random_id" "suffix" {
  byte_length = 4
}

###########################################
# 1. S3 Bucket with Static Website
###########################################
# This bucket will serve as a simple file listing
# and store any uploaded videos from FTP.

resource "aws_s3_bucket" "videos" {
  # unique name = videos-<random>
  bucket = "videos-${random_id.suffix.hex}"
  acl    = "public-read"

  # Enable static website hosting
  website {
    index_document = "index.html"
    error_document = "error.html"
  }
}

# For a public static website, we need to allow public read of objects.
resource "aws_s3_bucket_public_access_block" "videos" {
  bucket = aws_s3_bucket.videos.id
  block_public_acls   = false
  block_public_policy = false
  ignore_public_acls  = false
  restrict_public_buckets = false
}

# Bucket policy to allow public GET for all objects
resource "aws_s3_bucket_policy" "videos" {
  bucket = aws_s3_bucket.videos.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "PublicReadGetObject",
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.videos.arn}/*"
      }
    ]
  })
}

###########################################
# 2. IAM Role & Policy for Lambda
###########################################
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

# Grant Lambda permission to write logs and access S3
resource "aws_iam_role_policy" "lambda_exec_policy" {
  name = "ftp-sync-lambda-policy-${random_id.suffix.hex}"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Allow writing CloudWatch logs
      {
        Effect   = "Allow",
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      # Allow uploading + listing objects in our S3 bucket
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

###########################################
# 3. Package & Deploy the Lambda Function
###########################################
# We'll zip our Python code from local directory "lambda_code"
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_code"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "ftp_sync" {
  function_name = "ftp-sync-${random_id.suffix.hex}"
  description   = "Periodically downloads videos from FTP into S3"
  runtime       = "python3.9"
  handler       = "lambda_function.lambda_handler"
  role          = aws_iam_role.lambda_exec.arn

  filename            = data.archive_file.lambda_zip.output_path
  source_code_hash    = data.archive_file.lambda_zip.output_base64sha256
  publish             = true
  timeout             = 300  # seconds (5min). Increase for bigger files
  memory_size         = 512  # MB. Adjust if you expect bigger downloads

  # Environment variables for FTP info & bucket name
  environment {
    variables = {
      FTP_HOST    = var.ftp_host
      FTP_USER    = var.ftp_user
      FTP_PASS    = var.ftp_password
      BUCKET_NAME = aws_s3_bucket.videos.bucket
    }
  }
}

###########################################
# 4. EventBridge Rule to Schedule the Lambda
###########################################
resource "aws_cloudwatch_event_rule" "ftp_sync_rule" {
  name                = "ftp-sync-schedule-${random_id.suffix.hex}"
  description         = "Triggers the ftp_sync lambda on a schedule"
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

###########################################
# 5. (Optional) Upload a Starter Index Page
###########################################
# You can skip this if your Lambda or user manually uploads an index.html
# for demonstration, let's just put a simple "Hello, upload is not done yet" page
resource "null_resource" "upload_index" {
  provisioner "local-exec" {
    command = <<EOC
echo "<html><body><h1>Placeholder Index</h1><p>No videos yet. Lambda will upload them soon.</p></body></html>" > index.html
aws s3 cp index.html s3://${aws_s3_bucket.videos.bucket}/index.html --acl public-read --profile ${var.aws_profile} --region ${var.aws_region}
rm -f index.html
EOC
  }
  depends_on = [aws_s3_bucket.videos, aws_s3_bucket_public_access_block.videos]
}

###########################################
# 6. Output S3 Website Endpoint
###########################################
output "s3_website_url" {
  description = "Public URL for the S3 static website"
  value       = aws_s3_bucket.videos.website_endpoint
}
