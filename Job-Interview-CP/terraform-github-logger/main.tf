provider "aws" {
  region = "us-west-2"
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  ]
}

resource "null_resource" "install_layer_dependencies" {
  provisioner "local-exec" {
    command = "pip install -r layer/requirements.txt -t layer/python/lib/python3.9/site-packages"
  }
  triggers = {
    trigger = timestamp()
  }
}

data "archive_file" "layer_zip" {
  type        = "zip"
  source_dir  = "layer"
  output_path = "layer.zip"
  depends_on = [
    null_resource.install_layer_dependencies
  ]
}

resource "aws_lambda_layer_version" "lambda_layer" {
  filename = "layer.zip"
  source_code_hash = data.archive_file.layer_zip.output_base64sha256
  layer_name = "env-layer"

  compatible_runtimes = ["python3.9"]
  depends_on = [
    data.archive_file.layer_zip
  ]
}


resource "aws_lambda_function" "github_logger" {
  function_name = "github_logger"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  filename      = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  layers = [
    aws_lambda_layer_version.lambda_layer.arn
  ]
  environment {
    variables = {
      LOG_BUCKET = aws_s3_bucket.github_logs.bucket
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_logging_policy
  ]
}

resource "aws_s3_bucket" "github_logs" {
  bucket = "github-logs-v2"
}

# # resource "aws_s3_bucket" "exist_bucket" {
#   bucket = "new-logginpullrequest123"
# }

resource "aws_apigatewayv2_api" "github_webhook_api" {
  name          = "github_webhook_api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id             = aws_apigatewayv2_api.github_webhook_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.github_logger.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "github_webhook_route" {
  api_id    = aws_apigatewayv2_api.github_webhook_api.id
  route_key = "POST /webhook"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.github_webhook_api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_log_group.arn
    format          = jsonencode({
      requestId    = "$context.requestId"
      ip           = "$context.identity.sourceIp"
      caller       = "$context.identity.caller"
      user         = "$context.identity.user"
      requestTime  = "$context.requestTime"
      httpMethod   = "$context.httpMethod"
      resourcePath = "$context.resourcePath"
      status       = "$context.status"
      protocol     = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }
}


resource "aws_lambda_permission" "allow_apigateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.github_logger.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.github_webhook_api.execution_arn}/*/*"
}

resource "random_id" "bucket_id" {
  byte_length = 8
}

resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name = "/aws/apigateway/github_webhook_api"
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/github_logger"
}

resource "aws_iam_role_policy" "lambda_logging_policy" {
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = aws_cloudwatch_log_group.lambda_log_group.arn
      },
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Effect   = "Allow",
        Resource = [
          aws_s3_bucket.github_logs.arn,
          "${aws_s3_bucket.github_logs.arn}/*"
        ]
      }
    ]
  })
}
