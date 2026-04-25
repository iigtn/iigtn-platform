# ==============================================================================
# SNS Topic — アラーム通知のハブ
# ==============================================================================
resource "aws_sns_topic" "alarms" {
  name = "${var.name_prefix}-alarms"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ==============================================================================
# Lambda Errors Alarm
# ==============================================================================
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name_prefix}-lambda-errors"
  alarm_description   = "Contact Lambda errors > 1 over 5 min"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 1
  period              = 300
  statistic           = "Sum"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
  tags          = var.tags
}

# ==============================================================================
# Lambda Duration p95 Alarm
# ==============================================================================
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${var.name_prefix}-lambda-duration-p95"
  alarm_description   = "Contact Lambda p95 duration > 3s"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 3000
  period              = 300
  extended_statistic  = "p95"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  tags          = var.tags
}

# ==============================================================================
# API Gateway 5xx Alarm
# ==============================================================================
resource "aws_cloudwatch_metric_alarm" "apigw_5xx" {
  alarm_name          = "${var.name_prefix}-apigw-5xx"
  alarm_description   = "API Gateway 5xx errors > 5 over 5 min"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 5
  period              = 300
  statistic           = "Sum"
  metric_name         = "5xx"
  namespace           = "AWS/ApiGateway"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = var.api_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  tags          = var.tags
}

# Note: CloudFront 4xx alarm は us-east-1 必須。Terraform の provider alias
# がモジュール経由で効きにくかったため、envs/prod root に直接定義している。
# 本モジュールでは作らない。

# ==============================================================================
# AWS Budgets — 月額コスト超過アラート (alarm_email がセットされた時のみ作成)
# ==============================================================================
resource "aws_budgets_budget" "monthly" {
  count = var.alarm_email == "" ? 0 : 1

  name              = "${var.name_prefix}-monthly"
  budget_type       = "COST"
  limit_amount      = tostring(var.monthly_budget_usd)
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2026-04-01_00:00"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alarm_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alarm_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alarm_email]
  }
}
