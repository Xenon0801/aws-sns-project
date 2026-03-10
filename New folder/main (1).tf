# ============================================================
# PROJECT 2: Serverless REST API
# Services: API Gateway + Lambda + DynamoDB
# ============================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "eu-west-2"
}

# ----------------------------
# DYNAMODB TABLE
# ----------------------------
resource "aws_dynamodb_table" "users" {
  name         = "users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = { Name = "users-table" }
}

# ----------------------------
# IAM ROLE FOR LAMBDA
# ----------------------------
resource "aws_iam_role" "lambda_role" {
  name = "lambda-dynamodb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan"
      ]
      Resource = aws_dynamodb_table.users.arn
    }]
  })
}

# ----------------------------
# LAMBDA FUNCTION (Python)
# ----------------------------
# Write the Lambda code inline to a local file
resource "local_file" "lambda_code" {
  filename = "${path.module}/lambda/handler.py"
  content  = <<-PYTHON
import json
import boto3
import uuid
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('users')

def lambda_handler(event, context):
    http_method = event.get('httpMethod', '')
    path_params = event.get('pathParameters') or {}
    body = json.loads(event.get('body') or '{}')

    if http_method == 'POST':
        # CREATE user
        user_id = str(uuid.uuid4())
        item = {'id': user_id, **body}
        table.put_item(Item=item)
        return response(201, {'message': 'User created', 'id': user_id})

    elif http_method == 'GET' and path_params.get('id'):
        # GET single user
        result = table.get_item(Key={'id': path_params['id']})
        item = result.get('Item')
        if not item:
            return response(404, {'message': 'User not found'})
        return response(200, item)

    elif http_method == 'GET':
        # LIST all users
        result = table.scan()
        return response(200, result.get('Items', []))

    elif http_method == 'PUT' and path_params.get('id'):
        # UPDATE user
        table.put_item(Item={'id': path_params['id'], **body})
        return response(200, {'message': 'User updated'})

    elif http_method == 'DELETE' and path_params.get('id'):
        # DELETE user
        table.delete_item(Key={'id': path_params['id']})
        return response(200, {'message': 'User deleted'})

    return response(400, {'message': 'Unsupported method'})

def response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps(body, default=str)
    }
PYTHON
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
  depends_on  = [local_file.lambda_code]
}

resource "aws_lambda_function" "api_handler" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "users-api-handler"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tags = { Name = "users-api-handler" }
}

# ----------------------------
# API GATEWAY
# ----------------------------
resource "aws_api_gateway_rest_api" "users_api" {
  name        = "users-api"
  description = "Serverless REST API - Project 2"
}

resource "aws_api_gateway_resource" "users" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id
  parent_id   = aws_api_gateway_rest_api.users_api.root_resource_id
  path_part   = "users"
}

resource "aws_api_gateway_resource" "user_by_id" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id
  parent_id   = aws_api_gateway_resource.users.id
  path_part   = "{id}"
}

# Helper to create method + lambda integration
locals {
  methods = {
    "POST"   = aws_api_gateway_resource.users.id
    "GET"    = aws_api_gateway_resource.users.id
  }
}

resource "aws_api_gateway_method" "post_users" {
  rest_api_id   = aws_api_gateway_rest_api.users_api.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "get_users" {
  rest_api_id   = aws_api_gateway_rest_api.users_api.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "get_user" {
  rest_api_id   = aws_api_gateway_rest_api.users_api.id
  resource_id   = aws_api_gateway_resource.user_by_id.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "put_user" {
  rest_api_id   = aws_api_gateway_rest_api.users_api.id
  resource_id   = aws_api_gateway_resource.user_by_id.id
  http_method   = "PUT"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "delete_user" {
  rest_api_id   = aws_api_gateway_rest_api.users_api.id
  resource_id   = aws_api_gateway_resource.user_by_id.id
  http_method   = "DELETE"
  authorization = "NONE"
}

# Integrations (all point to same Lambda)
resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.users_api.id
  resource_id             = aws_api_gateway_resource.users.id
  http_method             = aws_api_gateway_method.post_users.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

resource "aws_api_gateway_integration" "get_users_integration" {
  rest_api_id             = aws_api_gateway_rest_api.users_api.id
  resource_id             = aws_api_gateway_resource.users.id
  http_method             = aws_api_gateway_method.get_users.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

resource "aws_api_gateway_integration" "get_user_integration" {
  rest_api_id             = aws_api_gateway_rest_api.users_api.id
  resource_id             = aws_api_gateway_resource.user_by_id.id
  http_method             = aws_api_gateway_method.get_user.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

resource "aws_api_gateway_integration" "put_integration" {
  rest_api_id             = aws_api_gateway_rest_api.users_api.id
  resource_id             = aws_api_gateway_resource.user_by_id.id
  http_method             = aws_api_gateway_method.put_user.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

resource "aws_api_gateway_integration" "delete_integration" {
  rest_api_id             = aws_api_gateway_rest_api.users_api.id
  resource_id             = aws_api_gateway_resource.user_by_id.id
  http_method             = aws_api_gateway_method.delete_user.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.users_api.execution_arn}/*/*"
}

# Deploy the API
resource "aws_api_gateway_deployment" "api_deploy" {
  rest_api_id = aws_api_gateway_rest_api.users_api.id

  depends_on = [
    aws_api_gateway_integration.post_integration,
    aws_api_gateway_integration.get_users_integration,
    aws_api_gateway_integration.get_user_integration,
    aws_api_gateway_integration.put_integration,
    aws_api_gateway_integration.delete_integration,
  ]
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api_deploy.id
  rest_api_id   = aws_api_gateway_rest_api.users_api.id
  stage_name    = "prod"
}

# ----------------------------
# OUTPUTS
# ----------------------------
output "api_base_url" {
  description = "Base URL for your REST API"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/users"
}

output "api_test_commands" {
  description = "Test commands to try after deployment"
  value       = <<-EOT
    # Create a user:
    curl -X POST ${aws_api_gateway_stage.prod.invoke_url}/users \
      -H "Content-Type: application/json" \
      -d '{"name":"Hardik","email":"hardik@example.com"}'

    # List all users:
    curl ${aws_api_gateway_stage.prod.invoke_url}/users
  EOT
}
