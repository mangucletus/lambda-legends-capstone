provider "aws" {
  region = "us-east-1"  # Adjust as needed
}

# Terraform State Backend
resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-bucket-capstone"
  acl    = "private"
  versioning {
    enabled = true
  }
}

terraform {
  backend "s3" {
    bucket = "terraform-state-bucket-capstone"
    key    = "capstone-project/terraform.tfstate"
    region = "us-east-1"
  }
}

# S3 Buckets for Translation
resource "aws_s3_bucket" "request_bucket" {
  bucket = "request-bucket-capstone"
  acl    = "private"
}

resource "aws_s3_bucket" "response_bucket" {
  bucket = "response-bucket-capstone"
  acl    = "private"
}

# IAM Role and Policy for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda-translation-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "translation_policy" {
  name = "translation-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["translate:TranslateText"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.request_bucket.arn,
          "${aws_s3_bucket.request_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.response_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.translation_policy.arn
}

# Lambda Function
resource "aws_lambda_function" "translation_lambda" {
  filename      = "lambda_function.zip"
  function_name = "translation_function"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.handler"
  runtime       = "python3.9"
  source_code_hash = filebase64sha256("lambda_function.zip")
}

# API Gateway
resource "aws_api_gateway_rest_api" "translation_api" {
  name = "translation-api"
}

resource "aws_api_gateway_resource" "translate_resource" {
  rest_api_id = aws_api_gateway_rest_api.translation_api.id
  parent_id   = aws_api_gateway_rest_api.translation_api.root_resource_id
  path_part   = "translate"
}

resource "aws_api_gateway_method" "translate_method" {
  rest_api_id   = aws_api_gateway_rest_api.translation_api.id
  resource_id   = aws_api_gateway_resource.translate_resource.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.translation_api.id
  resource_id             = aws_api_gateway_resource.translate_resource.id
  http_method             = aws_api_gateway_method.translate_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.translation_lambda.invoke_arn
}

resource "aws_api_gateway_deployment" "translation_deployment" {
  depends_on  = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.translation_api.id
  stage_name  = "prod"
}

resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.translation_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.translation_api.execution_arn}/*/*"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "translation-user-pool"
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "translation-app-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.translation_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

# S3 Bucket for Frontend
resource "aws_s3_bucket" "frontend_bucket" {
  bucket = "translation-frontend-bucket-capstone"
  acl    = "public-read"
  website {
    index_document = "index.html"
    error_document = "index.html"
  }
}

resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend_bucket.arn}/*"
    }]
  })
}

# Outputs
output "api_gateway_url" {
  value = "${aws_api_gateway_deployment.translation_deployment.invoke_url}/translate"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "frontend_url" {
  value = "http://${aws_s3_bucket.frontend_bucket.bucket}.s3-website-us-east-1.amazonaws.com"
}