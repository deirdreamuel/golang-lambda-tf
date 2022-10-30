terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "us-west-2"
}

# s3 bucket to store lambda source code
resource "aws_s3_bucket" "lambda_bucket" {
  bucket = "golang-lambda-bucket"

  tags = {
    Name        = "GoLang Lambda Bucket"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_acl" "bucket_acl" {
  bucket = aws_s3_bucket.lambda_bucket.id
  acl    = "private"
}

data "archive_file" "golang_lambda" {
    type = "zip"

    source_dir  = "${path.module}/../src/"
    output_path = "${path.module}/../src.zip"
}

resource "aws_s3_object" "golang_lambda" {
    bucket = aws_s3_bucket.lambda_bucket.id

    key    = "src.zip"
    source = data.archive_file.golang_lambda.output_path

    etag = filemd5(data.archive_file.golang_lambda.output_path)
}

# iam role for lambda
resource "aws_iam_role" "lambda_exec" {
  name = "serverless_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# lambda function, get from s3 bucket
resource "aws_lambda_function" "golang_lambda" {
    function_name = "golang_lambda"

    s3_bucket = aws_s3_bucket.lambda_bucket.id
    s3_key = aws_s3_object.golang_lambda.key

    runtime = "go1.x"
    handler = "main"

    source_code_hash = data.archive_file.golang_lambda.output_base64sha256
    role = aws_iam_role.lambda_exec.arn
}

# logs for lambda function
resource "aws_cloudwatch_log_group" "golang_lambda_logs" {
  name = "/aws/lambda/${aws_lambda_function.golang_lambda.function_name}"

  retention_in_days = 30
}

# api gateway endpoint
resource "aws_apigatewayv2_api" "apigw" {
  name          = "api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "live" {
  api_id = aws_apigatewayv2_api.apigw.id

  name        = "live"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "apigw_lambda_integration" {
  api_id = aws_apigatewayv2_api.apigw.id

  integration_uri    = aws_lambda_function.golang_lambda.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "main" {
  api_id = aws_apigatewayv2_api.apigw.id

  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.apigw_lambda_integration.id}"
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.golang_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.apigw.execution_arn}/*/*"
}

# logs for api gateway
resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.apigw.name}"

  retention_in_days = 30
}