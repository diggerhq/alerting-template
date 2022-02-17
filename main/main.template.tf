
terraform {
  required_version = ">= 0.12"

  # vars are not allowed in this block
  # see: https://github.com/hashicorp/terraform/issues/22088
  backend "s3" {}
}

provider "aws" {
  region     = var.region
  access_key = var.aws_key
  secret_key = var.aws_secret
}

locals {
  tags = {
    created_by : "digger"
  }

  lambda_function_name                = "${var.project}-${var.environment}-slack-notify-lambda"
  slack_notification_webhook_ssm_name = "/utils/slack/${var.project}/${var.environment}/webhook_url"
  sns_topic_name                      = "${var.project}_${var.environment}_cloudwatch_alarms"
  cloudwatch_log_group_name           = "/aws/lambda/${local.lambda_function_name}"

  lambda_handler = "lambda-function.lambda_handler"
  lambda_zip     = "${path.module}/lambda/lambda-function.zip"
  lambda_src     = "${path.module}/lambda/lambda-function.py"

  lambda_policy_document = {
    sid       = "AllowWriteToCloudwatchLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [aws_cloudwatch_log_group.lambda_log_group.arn]
  }

  lambda_ssm_policy_document = {
    sid       = "AllowToReadSSM"
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath", "ssm:PutParameter"]
    resources = [aws_ssm_parameter.slack_webhook_url_ssm.arn]
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "lambda_policy_document" {
  statement {
    sid       = local.lambda_policy_document.sid
    effect    = local.lambda_policy_document.effect
    actions   = local.lambda_policy_document.actions
    resources = local.lambda_policy_document.resources
  }
  statement {
    sid       = local.lambda_ssm_policy_document.sid
    effect    = local.lambda_ssm_policy_document.effect
    actions   = local.lambda_ssm_policy_document.actions
    resources = local.lambda_ssm_policy_document.resources
  }
}

resource "aws_sns_topic" "cloudwatch_alarms_topic" {
  name = local.sns_topic_name
}

resource "aws_ssm_parameter" "slack_webhook_url_ssm" {
  name        = local.slack_notification_webhook_ssm_name
  description = "Slack webhook URL"
  type        = "SecureString"
  value       = "test"

  lifecycle {
    ignore_changes = [value]
  }

  tags = local.tags
}

resource "aws_iam_role" "slack_notify_lambda_role" {
  name = "${var.project}_slack_notify_lambda_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

module "lambda" {
  source                            = "terraform-aws-modules/lambda/aws"
  function_name                     = local.lambda_function_name
  create_package                    = true
  package_type                      = "Zip"
  source_path                       = local.lambda_src
  runtime                           = "python3.8"
  timeout                           = 30
  publish                           = true
  handler                           = local.lambda_handler
  lambda_role                       = aws_iam_role.slack_notify_lambda_role.arn
  attach_cloudwatch_logs_policy     = false
  attach_policy_json                = true
  policy_json                       = try(data.aws_iam_policy_document.lambda_policy_document.json, "")
  use_existing_cloudwatch_log_group = true

  environment_variables = {
    ssm_webhook_url = aws_ssm_parameter.slack_webhook_url_ssm.arn
  }

  allowed_triggers = {
    AllowExecutionFromSNS = {
      principal  = "sns.amazonaws.com"
      source_arn = aws_sns_topic.cloudwatch_alarms_topic.arn
    }
  }
  tags       = local.tags
  depends_on = [aws_cloudwatch_log_group.lambda_log_group]
}

resource "aws_sns_topic_subscription" "sns-topic" {
  topic_arn = aws_sns_topic.cloudwatch_alarms_topic.arn
  protocol  = "lambda"
  endpoint  = module.lambda.lambda_function_arn
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = local.cloudwatch_log_group_name
  retention_in_days = 7
  tags              = local.tags
}

output "sns_topic_arn" {
  value = aws_sns_topic.cloudwatch_alarms_topic.arn
}

output "slack_notification_webhook_ssm_name" {
  value = local.slack_notification_webhook_ssm_name
}
